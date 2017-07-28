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

typedef NS_ENUM(NSUInteger, CKBadChangesetOperationType) {
  CKBadChangesetOperationTypeNone,
  CKBadChangesetOperationTypeUpdate,
  CKBadChangesetOperationTypeInsertSection,
  CKBadChangesetOperationTypeInsertRow,
  CKBadChangesetOperationTypeRemoveSection,
  CKBadChangesetOperationTypeRemoveRow,
  CKBadChangesetOperationTypeMoveSection,
  CKBadChangesetOperationTypeMoveRow
};

/** Returns a human readable translation of the given CKBadChangesetOperationType. */
NSString *CKHumanReadableBadChangesetOperationType(CKBadChangesetOperationType type);
