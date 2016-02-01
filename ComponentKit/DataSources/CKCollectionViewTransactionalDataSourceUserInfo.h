//
//  CKCollectionViewTransactionalDataSourceUserInfo.h
//  Sweeter
//
//  Created by Vlad Badea on 1/22/16.
//  Copyright © 2016 Vlad Badea. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CKCollectionViewTransactionalDataSourceUserInfo : NSObject

+ (instancetype)unpack:(NSDictionary*)userInfo;
- (NSDictionary*)pack;

- (instancetype)initWithUserInfo:(NSDictionary*)userInfo
       applyChangesWithAnimation:(BOOL)applyChangesWithAnimation;

@property(nonatomic, strong, readonly) NSDictionary *userInfo;
@property(nonatomic, assign, readonly) BOOL applyChangesWithAnimation;

@end
