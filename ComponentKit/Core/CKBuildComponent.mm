/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKBuildComponent.h"

#import "CKComponentBoundsAnimation.h"
#import "CKComponentBoundsAnimationPredicates.h"
#import "CKComponentInternal.h"
#import "CKComponentScopeRoot.h"
#import "CKComponentSubclass.h"
#import "CKThreadLocalComponentScope.h"

CKBuildComponentResult CKBuildComponent(CKComponentScopeRoot *previousRoot,
                                        const CKComponentStateUpdateMap &stateUpdates,
                                        CKComponent *(^componentFactory)(void))
{
  CKCAssertNotNil(componentFactory, @"Must have component factory to build a component");
  CKThreadLocalComponentScope threadScope(previousRoot, stateUpdates);
  // Order of operations matters, so first store into locals and then return a struct.
  CKComponent *const component = componentFactory();
  return {
    .component = component,
    .scopeRoot = threadScope.newScopeRoot,
    .boundsAnimation = CKComponentBoundsAnimationFromPreviousScopeRoot(threadScope.newScopeRoot, previousRoot)
  };
}

