/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKButtonComponent.h"

#import <array>

#import <ComponentKit/CKAssert.h>

#import "CKInternalHelpers.h"
#import "CKComponentSubclass.h"

struct CKStateConfiguration {
  NSString *title;
  UIColor *titleColor;
  UIImage *image;
  UIImage *backgroundImage;
  
  bool operator==(const CKStateConfiguration &other) const
  {
    return CKObjectIsEqual(title, other.title)
    && CKObjectIsEqual(titleColor, other.titleColor)
    && CKObjectIsEqual(image, other.image)
    && CKObjectIsEqual(backgroundImage, other.backgroundImage);
  }
};

/** Use indexForState to map from UIControlState to an array index. */
typedef std::array<CKStateConfiguration, 8> CKStateConfigurationArray;

@interface CKButtonComponentConfiguration : NSObject
{
@public
  CKStateConfigurationArray _configurations;
  NSUInteger _precomputedHash;
}
@end

@implementation CKButtonComponent
{
  CGSize _intrinsicSize;
}

+ (instancetype)newWithAction:(const CKTypedComponentAction<UIEvent *>)action
                      options:(const CKButtonComponentOptions &)options
{
  static const CKComponentViewAttribute titleFontAttribute = {"CKButtonComponent.titleFont", ^(UIButton *button, id value) {
    button.titleLabel.font = value;
  }};
  
  static const CKComponentViewAttribute configurationAttribute = {
    "CKButtonComponent.config",
    ^(UIButton *view, CKButtonComponentConfiguration *config) {
      enumerateAllStates(^(UIControlState state) {
        const CKStateConfiguration &stateConfig = config->_configurations[indexForState(state)];
        if (stateConfig.title) {
          [view setTitle:stateConfig.title forState:state];
        }
        if (stateConfig.titleColor) {
          [view setTitleColor:stateConfig.titleColor forState:state];
        }
        if (stateConfig.image) {
          [view setImage:stateConfig.image forState:state];
        }
        if (stateConfig.backgroundImage) {
          [view setBackgroundImage:stateConfig.backgroundImage forState:state];
        }
      });
    },
    // No unapplicator.
    nil,
    ^(UIButton *view, CKButtonComponentConfiguration *oldConfig, CKButtonComponentConfiguration *newConfig) {
      enumerateAllStates(^(UIControlState state) {
        const CKStateConfiguration &oldStateConfig = oldConfig->_configurations[indexForState(state)];
        const CKStateConfiguration &newStateConfig = newConfig->_configurations[indexForState(state)];
        if (!CKObjectIsEqual(oldStateConfig.title, newStateConfig.title)) {
          [view setTitle:newStateConfig.title forState:state];
        }
        if (!CKObjectIsEqual(oldStateConfig.titleColor, newStateConfig.titleColor)) {
          [view setTitleColor:newStateConfig.titleColor forState:state];
        }
        if (!CKObjectIsEqual(oldStateConfig.image, newStateConfig.image)) {
          [view setImage:newStateConfig.image forState:state];
        }
        if (!CKObjectIsEqual(oldStateConfig.backgroundImage, newStateConfig.backgroundImage)) {
          [view setBackgroundImage:newStateConfig.backgroundImage forState:state];
        }
      });
    }
  };
  
  CKViewComponentAttributeValueMap attributes(options.attributes);
  attributes.insert({
    {configurationAttribute, configurationFromOptions(options)},
    {titleFontAttribute, options.titleFont},
    {@selector(setSelected:), options.selected},
    {@selector(setEnabled:), options.enabled},
    CKComponentActionAttribute(action, UIControlEventTouchUpInside),
  });
  
  UIEdgeInsets contentEdgeInsets = UIEdgeInsetsZero;
  const auto it = options.attributes.find(@selector(setContentEdgeInsets:));
  if (it != options.attributes.end()) {
    contentEdgeInsets = [it->second UIEdgeInsetsValue];
  }
  
  CKComponentAccessibilityContext accessibilityContext(options.accessibilityContext);
  if (!accessibilityContext.accessibilityComponentAction) {
    accessibilityContext.accessibilityComponentAction = options.enabled
    ? CKUntypedComponentAction::demotedFrom(action, static_cast<UIEvent*>(nil))
    : nullptr;
  }
  
  const auto b = [super
                  newWithView:{
                    [UIButton class],
                    std::move(attributes),
                    std::move(accessibilityContext)
                  }
                  size:options.size];
  
#if !TARGET_OS_TV
  const UIControlState state = (options.selected ? UIControlStateSelected : UIControlStateNormal)
  | (options.enabled ? UIControlStateNormal : UIControlStateDisabled);
  b->_intrinsicSize = intrinsicSize(valueForState(options.titles.getMap(), state),
                                    options.titleFont,
                                    valueForState(options.images.getMap(), state),
                                    valueForState(options.backgroundImages.getMap(), state),
                                    contentEdgeInsets);
#else
  // intrinsicSize not available on tvOS (can't use `sizeWithFont`) so set to infinity
  b->_intrinsicSize = {INFINITY, INFINITY};
#endif // !TARGET_OS_TV
  return b;
}

- (CKComponentLayout)computeLayoutThatFits:(CKSizeRange)constrainedSize
{
  return {self, constrainedSize.clamp(_intrinsicSize)};
}

static CKButtonComponentConfiguration *configurationFromOptions(const CKButtonComponentOptions &options)
{
  CKButtonComponentConfiguration *const config = [[CKButtonComponentConfiguration alloc] init];
  CKStateConfigurationArray &configs = config->_configurations;
  NSUInteger hash = 0;
  for (const auto it : options.titles.getMap()) {
    configs[indexForState(it.first)].title = it.second;
    hash ^= (it.first ^ [it.second hash]);
  }
  for (const auto it : options.titleColors.getMap()) {
    configs[indexForState(it.first)].titleColor = it.second;
    hash ^= (it.first ^ [it.second hash]);
  }
  for (const auto it : options.images.getMap()) {
    configs[indexForState(it.first)].image = it.second;
    hash ^= (it.first ^ [it.second hash]);
  }
  for (const auto it : options.backgroundImages.getMap()) {
    configs[indexForState(it.first)].backgroundImage = it.second;
    hash ^= (it.first ^ [it.second hash]);
  }
  config->_precomputedHash = hash;
  return config;
}

template<typename T>
static T valueForState(const std::unordered_map<UIControlState, T> &m, UIControlState state)
{
  auto it = m.find(state);
  if (it != m.end()) {
    return it->second;
  }
  // "If a title is not specified for a state, the default behavior is to use the title associated with the
  // UIControlStateNormal state." (Similarly for other attributes.)
  it = m.find(UIControlStateNormal);
  if (it != m.end()) {
    return it->second;
  }
  return nil;
}

#if !TARGET_OS_TV // sizeWithFont is not available on tvOS
static CGSize intrinsicSize(NSString *title, UIFont *titleFont, UIImage *image,
                            UIImage *backgroundImage, UIEdgeInsets contentEdgeInsets)
{
  // This computation is based on observing [UIButton -sizeThatFits:], which uses the deprecated method
  // sizeWithFont in iOS 7 and iOS 8
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
  const CGSize titleSize = [title sizeWithFont:titleFont ?: [UIFont systemFontOfSize:[UIFont buttonFontSize]]];
#pragma clang diagnostic pop
  const CGSize imageSize = image.size;
  const CGSize contentSize = {
    titleSize.width + imageSize.width + contentEdgeInsets.left + contentEdgeInsets.right,
    MAX(titleSize.height, imageSize.height) + contentEdgeInsets.top + contentEdgeInsets.bottom
  };
  const CGSize backgroundImageSize = backgroundImage.size;
  return {
    MAX(backgroundImageSize.width, contentSize.width),
    MAX(backgroundImageSize.height, contentSize.height)
  };
}
#endif // !TARGET_OS_TV

/**
 Note this only enumerates through the default UIControlStates, not any application-defined or system-reserved ones.
 It excludes any states with both UIControlStateHighlighted and UIControlStateDisabled set as that is an invalid value.
 (UIButton will, surprisingly enough, throw away one of the bits if they are set together instead of ignoring it.)
 */
static void enumerateAllStates(void (^block)(UIControlState))
{
  for (int highlighted = 0; highlighted < 2; highlighted++) {
    for (int disabled = 0; disabled < 2; disabled++) {
      for (int selected = 0; selected < 2; selected++) {
        const UIControlState state = (highlighted ? UIControlStateHighlighted : 0) | (disabled ? UIControlStateDisabled : 0) | (selected ? UIControlStateSelected : 0);
        if (state & UIControlStateHighlighted && state & UIControlStateDisabled) {
          continue;
        }
        if (block) {
          block(state);
        }
      }
    }
  }
}

static inline NSUInteger indexForState(UIControlState state)
{
  return 0 +
  (state & UIControlStateHighlighted ? 4 : 0) +
  (state & UIControlStateDisabled ? 2 : 0) +
  (state & UIControlStateSelected ? 1 : 0);
}

@end

@implementation CKButtonComponentConfiguration

- (BOOL)isEqual:(id)object
{
  if (self == object) {
    return YES;
  } else if ([object isKindOfClass:[self class]]) {
    CKButtonComponentConfiguration *const other = object;
    return _configurations == other->_configurations;
  }
  return NO;
}

- (NSUInteger)hash
{
  return _precomputedHash;
}

@end
