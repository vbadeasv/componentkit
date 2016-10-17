/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKStackUnpositionedLayout.h"

#import <numeric>

#import <ComponentKit/CKAssert.h>

#import "ComponentUtilities.h"
#import "CKComponentInternal.h"
#import "CKComponentSubclass.h"
#import "CKStackLayoutComponentUtilities.h"

static CGFloat resolveCrossDimensionMaxForStretchChild(const CKStackLayoutComponentStyle &style,
                                                       const CKStackLayoutComponentChild &child,
                                                       const CGFloat stackMax,
                                                       const CGFloat crossMax)
{
  // stretched children may have a cross direction max that is smaller than the minimum size constraint of the parent.
  const CGFloat computedMax = (style.direction == CKStackLayoutDirectionVertical ?
                               child.component.size.resolve(kCKComponentParentSizeUndefined).max.width :
                               child.component.size.resolve(kCKComponentParentSizeUndefined).max.height);
  return computedMax == INFINITY ? crossMax : computedMax;
}

static CGFloat resolveCrossDimensionMinForStretchChild(const CKStackLayoutComponentStyle &style,
                                                    const CKStackLayoutComponentChild &child,
                                                    const CGFloat stackMax,
                                                    const CGFloat crossMin)
{
  // stretched children will have a cross dimension of at least crossMin, unless they explicitly define a child size
  // that is smaller than the constraint of the parent.
  return (style.direction == CKStackLayoutDirectionVertical ?
             child.component.size.resolve(kCKComponentParentSizeUndefined).min.width :
          child.component.size.resolve(kCKComponentParentSizeUndefined).min.height) ?: crossMin;
}

/**
 Sizes the child given the parameters specified, and returns the computed layout.

 @param size the size of the stack layout component. May be undefined in either or both directions.
 */
static CKComponentLayout crossChildLayout(const CKStackLayoutComponentChild &child,
                                          const CKStackLayoutComponentStyle style,
                                          const CGFloat stackMin,
                                          const CGFloat stackMax,
                                          const CGFloat crossMin,
                                          const CGFloat crossMax,
                                          const CGSize size)
{
  const CKStackLayoutAlignItems alignItems = alignment(child.alignSelf, style.alignItems);
  const CGFloat childCrossMin = (alignItems == CKStackLayoutAlignItemsStretch ?
                                 resolveCrossDimensionMinForStretchChild(style, child, stackMax, crossMin) :
                                 0);
  const CGFloat childCrossMax = (alignItems == CKStackLayoutAlignItemsStretch ?
                                 resolveCrossDimensionMaxForStretchChild(style, child, stackMax, crossMax) :
                                 crossMax);
  const CKSizeRange childSizeRange = directionSizeRange(style.direction, stackMin, stackMax, childCrossMin, childCrossMax);
  return CKComputeComponentLayout(child.component, childSizeRange, size);
}

/**
 Stretches children to lay out along the cross axis according to the alignment stretch settings of the children
 (child.alignSelf), and the stack layout's alignment settings (style.alignItems).  This does not do the actual alignment
 of the items once stretched though; CKStackPositionedLayout will do centering etc.

 Finds the maximum cross dimension among child layouts.  If that dimension exceeds the minimum cross layout size then
 we must stretch any children whose alignItems specify CKStackLayoutAlignItemsStretch.

 The diagram below shows 3 children in a horizontal stack.  The second child is larger than the minCrossDimension, so
 its height is used as the childCrossMax.  Any children that are stretchable (which may be all children if
 style.alignItems specifies stretch) like the first child must be stretched to match that maximum.  All children must be
 at least minCrossDimension in cross dimension size, which is shown by the sizing of the third child.

                 Stack Dimension
                 +--------------------->
              +  +-+-------------+-+-------------+--+---------------+  + + +
              |    | child.      | |             |  |               |  | | |
              |    | alignSelf   | |             |  |               |  | | |
 Cross        |    | = stretch   | |             |  +-------+-------+  | | |
 Dimension    |    +-----+-------+ |             |  |       |       |  | | |
              |    |     |       | |             |          |          | | |
              |          |         |             |  |       v       |  | | |
              v  +-+- - - - - - -+-+ - - - - - - +--+- - - - - - - -+  | | + minCrossDimension
                         |         |             |                     | |
                   |     v       | |             |                     | |
                   +- - - - - - -+ +-------------+                     | + childCrossMax
                                                                       |
                 +--------------------------------------------------+  + crossMax

 @param layouts pre-computed child layouts; modified in-place as needed
 @param style the layout style of the overall stack layout
 @param size the size of the stack layout component. May be undefined in either or both directions.
 */
static void stretchChildrenAlongCrossDimension(std::vector<CKStackUnpositionedItem> &layouts,
                                               const CKStackLayoutComponentStyle &style,
                                               const CGSize size)
{
  // Find the maximum cross dimension size among child layouts
  const auto it = std::max_element(layouts.begin(), layouts.end(),
                                   [&](const CKStackUnpositionedItem &a, const CKStackUnpositionedItem &b) {
                                     return compareCrossDimension(style.direction, a.layout.size, b.layout.size);
                                   });

  const CGFloat childCrossMax = it == layouts.end() ? 0 : crossDimension(style.direction, it->layout.size);
  for (auto &l : layouts) {
    const CKStackLayoutAlignItems alignItems = alignment(l.child.alignSelf, style.alignItems);

    const CGFloat cross = crossDimension(style.direction, l.layout.size);
    const CGFloat stack = stackDimension(style.direction, l.layout.size);

    // restretch all stretchable children along the cross axis using the new min. set their max size to childCrossMax,
    // not crossMax, so that if any of them would choose a larger size just because the min size increased (weird!)
    // they are forced to choose the same width as all the other components.
    if (alignItems == CKStackLayoutAlignItemsStretch && fabs(cross - childCrossMax) > 0.01) {
      l.layout = crossChildLayout(l.child, style, stack, stack, childCrossMax, childCrossMax, size);
    }
  }
}

/** The threshold that determines if a violation has actually occurred. */
static const CGFloat kViolationEpsilon = 0.01;

/**
 Returns a lambda that computes the relevant flex factor based on the given violation.
 @param violation The amount that the stack layout violates its size range.  See header for sign interpretation.
 */
static std::function<CGFloat(const CKStackUnpositionedItem &)> flexFactorInViolationDirection(const CGFloat violation)
{
  if (fabs(violation) < kViolationEpsilon) {
    return [](const CKStackUnpositionedItem &item) { return 0.0; };
  } else if (violation > 0) {
    return [](const CKStackUnpositionedItem &item) { return item.child.flexGrow; };
  } else {
    return [](const CKStackUnpositionedItem &item) { return item.child.flexShrink; };
  }
}

static inline CGFloat scaledFlexShrinkFactor(const CKStackUnpositionedItem &item,
                                             const CKStackLayoutComponentStyle &style,
                                             const CGFloat flexFactorSum)
{
  return stackDimension(style.direction, item.layout.size) * (item.child.flexShrink / flexFactorSum);
}

/**
 Returns a lambda that computes a flex shrink adjustment for a given item based on the provided violation.
 @param items The unpositioned items from the original unconstrained layout pass.
 @param style The layout style to be applied to all children.
 @param violation The amount that the stack layout violates its size range.
 @param flexFactorSum The sum of each item's flex factor as determined by the provided violation.
 @return A lambda capable of computing the flex shrink adjustment, if any, for a particular item.
 */
static std::function<CGFloat(const CKStackUnpositionedItem &)> flexShrinkAdjustment(const std::vector<CKStackUnpositionedItem> &items,
                                                                                    const CKStackLayoutComponentStyle &style,
                                                                                    const CGFloat violation,
                                                                                    const CGFloat flexFactorSum)
{
  const CGFloat scaledFlexShrinkFactorSum = std::accumulate(items.begin(), items.end(), 0.0, [&](CGFloat x, const CKStackUnpositionedItem &item) {
    return x + scaledFlexShrinkFactor(item, style, flexFactorSum);
  });
  return [style, scaledFlexShrinkFactorSum, violation, flexFactorSum](const CKStackUnpositionedItem &item) {
    const CGFloat scaledFlexShrinkFactorRatio = scaledFlexShrinkFactor(item, style, flexFactorSum) / scaledFlexShrinkFactorSum;
    // The item should shrink proportionally to the scaled flex shrink factor ratio computed above.
    // Unlike the flex grow adjustment the flex shrink adjustment needs to take the size of each item into account.
    return -fabs(scaledFlexShrinkFactorRatio * violation);
  };
}

/**
 Returns a lambda that computes a flex grow adjustment for a given item based on the provided violation.
 @param items The unpositioned items from the original unconstrained layout pass.
 @param violation The amount that the stack layout violates its size range.
 @param flexFactorSum The sum of each item's flex factor as determined by the provided violation.
 @return A lambda capable of computing the flex grow adjustment, if any, for a particular item.
 */
static std::function<CGFloat(const CKStackUnpositionedItem &)> flexGrowAdjustment(const std::vector<CKStackUnpositionedItem> &items,
                                                                                  const CGFloat violation,
                                                                                  const CGFloat flexFactorSum)
{
  // To compute the flex grow adjustment distribute the violation proportionally based on each item's flex grow factor.
  return [violation, flexFactorSum](const CKStackUnpositionedItem &item) {
    return floorf(violation * (item.child.flexGrow / flexFactorSum));
  };
}

/**
 Returns a lambda that computes a flex adjustment for a given item based on the provided violation.
 @param items The unpositioned items from the original unconstrained layout pass.
 @param style The layout style to be applied to all children.
 @param violation The amount that the stack layout violates its size range.
 @param flexFactorSum The sum of each item's flex factor as determined by the provided violation.
 @return A lambda capable of computing the flex adjustment for a particular item.
 */
static std::function<CGFloat(const CKStackUnpositionedItem &)> flexAdjustmentInViolationDirection(const std::vector<CKStackUnpositionedItem> &items,
                                                                                                  const CKStackLayoutComponentStyle &style,
                                                                                                  const CGFloat violation,
                                                                                                  const CGFloat flexFactorSum)
{
  if (violation > 0) {
    return flexGrowAdjustment(items, violation, flexFactorSum);
  } else {
    return flexShrinkAdjustment(items, style, violation, flexFactorSum);
  }
}

static inline BOOL isFlexibleInBothDirections(const CKStackLayoutComponentChild &child)
{
  return child.flexGrow > 0 && child.flexShrink > 0;
}

/**
 The flexible children may have been left not laid out in the initial layout pass, so we may have to go through and size
 these children at zero size so that the children layouts are at least present.
 */
static void layoutFlexibleChildrenAtZeroSize(std::vector<CKStackUnpositionedItem> &items,
                                             const CKStackLayoutComponentStyle &style,
                                             const CKSizeRange &sizeRange,
                                             const CGSize size)
{
  for (CKStackUnpositionedItem &item : items) {
    if (isFlexibleInBothDirections(item.child)) {
      item.layout = crossChildLayout(item.child,
                                     style,
                                     0,
                                     0,
                                     crossDimension(style.direction, sizeRange.min),
                                     crossDimension(style.direction, sizeRange.max),
                                     size);
    }
  }
}

/**
 Computes the consumed stack dimension length for the given vector of children and stacking style.

              stackDimensionSum
          <----------------------->
          +-----+  +-------+  +---+
          |     |  |       |  |   |
          |     |  |       |  |   |
          +-----+  |       |  +---+
                   +-------+

 @param children unpositioned layouts for the child components of the stack component
 @param style the layout style of the overall stack layout
 */
static CGFloat computeStackDimensionSum(const std::vector<CKStackUnpositionedItem> &children,
                                        const CKStackLayoutComponentStyle &style)
{
  // Sum up the childrens' spacing
  const CGFloat childSpacingSum = std::accumulate(children.begin(), children.end(),
                                                  // Start from default spacing between each child:
                                                  children.empty() ? 0 : style.spacing * (children.size() - 1),
                                                  [&](CGFloat x, const CKStackUnpositionedItem &l) {
                                                    return x + l.child.spacingBefore + l.child.spacingAfter;
                                                  });

  // Sum up the childrens' dimensions (including spacing) in the stack direction.
  const CGFloat childStackDimensionSum = std::accumulate(children.begin(), children.end(), childSpacingSum,
                                                         [&](CGFloat x, const CKStackUnpositionedItem &l) {
                                                           return x + stackDimension(style.direction, l.layout.size);
                                                         });
  return childStackDimensionSum;
}

/**
 Computes the violation by comparing a stack dimension sum with the overall allowable size range for the stack.

 Violation is the distance you would have to add to the unbounded stack-direction length of the stack component's
 children in order to bring the stack within its allowed sizeRange.  The diagram below shows 3 horizontal stacks with
 the different types of violation.

                                          sizeRange
                                       |------------|
       +------+ +-------+ +-------+ +---------+
       |      | |       | |       | |  |      |     |
       |      | |       | |       | |         | (zero violation)
       |      | |       | |       | |  |      |     |
       +------+ +-------+ +-------+ +---------+
                                       |            |
       +------+ +-------+ +-------+
       |      | |       | |       |    |            |
       |      | |       | |       |<--> (positive violation)
       |      | |       | |       |    |            |
       +------+ +-------+ +-------+
                                       |            |<------> (negative violation)
       +------+ +-------+ +-------+ +---------+ +-----------+
       |      | |       | |       | |  |      | |   |       |
       |      | |       | |       | |         | |           |
       |      | |       | |       | |  |      | |   |       |
       +------+ +-------+ +-------+ +---------+ +-----------+

 @param stackDimensionSum the consumed length of the children in the stack along the stack dimension
 @param style layout style to be applied to all children
 @param sizeRange the range of allowable sizes for the stack layout component
 */
static CGFloat computeViolation(const CGFloat stackDimensionSum,
                                const CKStackLayoutComponentStyle &style,
                                const CKSizeRange &sizeRange)
{
  const CGFloat minStackDimension = stackDimension(style.direction, sizeRange.min);
  const CGFloat maxStackDimension = stackDimension(style.direction, sizeRange.max);
  if (stackDimensionSum < minStackDimension) {
    return minStackDimension - stackDimensionSum;
  } else if (stackDimensionSum > maxStackDimension) {
    return maxStackDimension - stackDimensionSum;
  }
  return 0;
}

/**
 Flexes children in the stack axis to resolve a min or max stack size violation. First, determines which children are
 flexible (see computeViolation and isFlexibleInViolationDirection). Then computes how much to flex each flexible child
 and performs re-layout. Note that there may still be a non-zero violation even after flexing.

 The actual CSS flexbox spec describes an iterative looping algorithm here, which may be adopted in t5837937:
 http://www.w3.org/TR/css3-flexbox/#resolve-flexible-lengths

 @param items Reference to unpositioned items from the original, unconstrained layout pass; modified in-place
 @param style layout style to be applied to all children
 @param sizeRange the range of allowable sizes for the stack layout component
 @param size Size of the stack layout component. May be undefined in either or both directions.
 */
static void flexChildrenAlongStackDimension(std::vector<CKStackUnpositionedItem> &items,
                                            const CKStackLayoutComponentStyle &style,
                                            const CKSizeRange &sizeRange,
                                            const CGSize size,
                                            const BOOL useOptimizedFlexing)
{
  const CGFloat violation = computeViolation(computeStackDimensionSum(items, style), style, sizeRange);
  std::function<CGFloat(const CKStackUnpositionedItem &)> flexFactor = flexFactorInViolationDirection(violation);
  // The flex factor sum is needed to determine if flexing is necessary.
  // This value is also needed if the violation is positive and flexible children need to grow, so keep it around.
  const CGFloat flexFactorSum = std::accumulate(items.begin(), items.end(), 0.0, [&](CGFloat x, const CKStackUnpositionedItem &item) {
    return x + flexFactor(item);
  });
  // If no children are able to flex then there is nothing left to do. Bail.
  if (flexFactorSum == 0) {
    // If optimized flexing was used then we have to clean up the unsized children and lay them out at zero size.
    if (useOptimizedFlexing) {
      layoutFlexibleChildrenAtZeroSize(items, style, sizeRange, size);
    }
    return;
  }
  std::function<CGFloat(const CKStackUnpositionedItem &)> flexAdjustment = flexAdjustmentInViolationDirection(items,
                                                                                                              style,
                                                                                                              violation,
                                                                                                              flexFactorSum);

  // Compute any remaining violation. Any remaining violation it will be allocated to the first flexible child.
  const CGFloat remainingViolation = std::accumulate(items.begin(), items.end(), violation, [&](CGFloat x, const CKStackUnpositionedItem &item) {
    return x - flexAdjustment(item);
  });
  BOOL isFirstFlex = YES;
  for (CKStackUnpositionedItem &item : items) {
    const CGFloat currentFlexAdjustment = flexAdjustment(item);
    // Children are consider inflexible if they do not need to make a flex adjustment.
    if (currentFlexAdjustment != 0) {
      const CGFloat originalStackSize = stackDimension(style.direction, item.layout.size);
      // Only apply the remaining violation for the first flexible child that has a flex grow factor.
      const CGFloat flexedStackSize = originalStackSize + currentFlexAdjustment + (isFirstFlex && item.child.flexGrow > 0 ? remainingViolation : 0);
      item.layout = crossChildLayout(item.child,
                                     style,
                                     MAX(flexedStackSize, 0),
                                     MAX(flexedStackSize, 0),
                                     crossDimension(style.direction, sizeRange.min),
                                     crossDimension(style.direction, sizeRange.max),
                                     size);
      isFirstFlex = NO;
    }
  }
}

/**
 Performs the first unconstrained layout of the children, generating the unpositioned items that are then flexed and
 stretched.
 */
static std::vector<CKStackUnpositionedItem> layoutChildrenAlongUnconstrainedStackDimension(const std::vector<CKStackLayoutComponentChild> &children,
                                                                                           const CKStackLayoutComponentStyle &style,
                                                                                           const CKSizeRange &sizeRange,
                                                                                           const CGSize size,
                                                                                           const BOOL useOptimizedFlexing)
{
  const CGFloat minCrossDimension = crossDimension(style.direction, sizeRange.min);
  const CGFloat maxCrossDimension = crossDimension(style.direction, sizeRange.max);
  return CK::map(children, [&](const CKStackLayoutComponentChild &child) -> CKStackUnpositionedItem {
    if (useOptimizedFlexing && isFlexibleInBothDirections(child)) {
      return { child, { child.component, {0, 0} } };
    } else {
      return {
        child,
        crossChildLayout(child,
                         style,
                         child.flexBasis.resolve(0, stackDimension(style.direction, size)),
                         child.flexBasis.resolve(INFINITY, stackDimension(style.direction, size)),
                         minCrossDimension,
                         maxCrossDimension,
                         size)
      };
    }
  });
}

/**
 If we have a single flexible (both shrinkable and growable) child, and our allowed size range is set to a specific
 number then we may avoid the first "intrinsic" size calculation.
 */
static inline BOOL useOptimizedFlexing(const std::vector<CKStackLayoutComponentChild> &children,
                                       const CKStackLayoutComponentStyle &style,
                                       const CKSizeRange &sizeRange)
{
  const NSUInteger flexibleChildren = std::count_if(children.begin(), children.end(), isFlexibleInBothDirections);
  return ((flexibleChildren == 1)
          && (stackDimension(style.direction, sizeRange.min) ==
              stackDimension(style.direction, sizeRange.max)));
}

CKStackUnpositionedLayout CKStackUnpositionedLayout::compute(const std::vector<CKStackLayoutComponentChild> &children,
                                                             const CKStackLayoutComponentStyle &style,
                                                             const CKSizeRange &sizeRange)
{
  // If we have a fixed size in either dimension, pass it to children so they can resolve percentages against it.
  // Otherwise, we pass kCKComponentParentDimensionUndefined since it will depend on the content.
  const CGSize size = {
    (sizeRange.min.width == sizeRange.max.width) ? sizeRange.min.width : kCKComponentParentDimensionUndefined,
    (sizeRange.min.height == sizeRange.max.height) ? sizeRange.min.height : kCKComponentParentDimensionUndefined,
  };

  // We may be able to avoid some redundant layout passes
  const BOOL optimizedFlexing = useOptimizedFlexing(children, style, sizeRange);

  // We do a first pass of all the children, generating an unpositioned layout for each with an unbounded range along
  // the stack dimension.  This allows us to compute the "intrinsic" size of each child and find the available violation
  // which determines whether we must grow or shrink the flexible children.
  std::vector<CKStackUnpositionedItem> items = layoutChildrenAlongUnconstrainedStackDimension(children,
                                                                                              style,
                                                                                              sizeRange,
                                                                                              size,
                                                                                              optimizedFlexing);

  flexChildrenAlongStackDimension(items, style, sizeRange, size, optimizedFlexing);
  stretchChildrenAlongCrossDimension(items, style, size);

  const CGFloat stackDimensionSum = computeStackDimensionSum(items, style);
  return {std::move(items), stackDimensionSum, computeViolation(stackDimensionSum, style, sizeRange)};
}
