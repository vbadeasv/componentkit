/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <Foundation/Foundation.h>

#import <ComponentKit/CKInvalidChangesetOperationType.h>

@class CKDataSourceChangeset;
@class CKTransactionalComponentDataSourceState;

@protocol CKTransactionalComponentDataSourceStateModifying;

CKInvalidChangesetOperationType CKIsValidChangesetForState(CKDataSourceChangeset *changeset,
                                                           CKTransactionalComponentDataSourceState *state,
                                                           NSArray<id<CKTransactionalComponentDataSourceStateModifying>> *pendingAsynchronousModifications);
