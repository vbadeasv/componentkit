//
//  CKCollectionViewTransactionalDataSourceUserInfo.m
//  Sweeter
//
//  Created by Vlad Badea on 1/22/16.
//  Copyright © 2016 Vlad Badea. All rights reserved.
//

#import "CKCollectionViewTransactionalDataSourceUserInfo.h"

static NSString *const UserInfoKey                    = @"UserInfo";
static NSString *const ApplyChangesWithAnimationKey   = @"ApplyChangesWithAnimation";

@interface CKCollectionViewTransactionalDataSourceUserInfo()
@property(nonatomic, strong, readwrite) NSDictionary *userInfo;
@property(nonatomic, assign, readwrite) BOOL applyChangesWithAnimation;
@end

@implementation CKCollectionViewTransactionalDataSourceUserInfo

+ (instancetype)unpack:(NSDictionary*)userInfo
{
  return [[self alloc] initWithUserInfo:userInfo[UserInfoKey]
              applyChangesWithAnimation:[userInfo[ApplyChangesWithAnimationKey] boolValue]];
}

- (NSDictionary*)pack
{
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  [dictionary setValue:self.userInfo forKey:UserInfoKey];
  [dictionary setValue:@(self.applyChangesWithAnimation) forKey:UserInfoKey];
  return dictionary;
}

- (instancetype)initWithUserInfo:(NSDictionary*)userInfo
       applyChangesWithAnimation:(BOOL)applyChangesWithAnimation
{
  self = [super init];
  if (!self) return nil;

  self.userInfo = userInfo;
  self.applyChangesWithAnimation = applyChangesWithAnimation;

  return self;
}

@end
