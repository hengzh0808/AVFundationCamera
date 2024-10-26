//
//  ViewController.h
//  RACustomCamera
//
//  Created by Rocky on 15/9/22.
//  Copyright © 2015年 Rocky. All rights reserved.
//

#import <UIKit/UIKit.h>


typedef NS_OPTIONS(NSUInteger, Options) {
    OptionsNone   = 0,
    OptionsA      = 1 << 0,
    OptionsB      = 1 << 1,
    OptionsC      = 1 << 2,
};

@protocol ViewControllerDelegate <NSObject>

@optional
- (void)photoCapViewController:(UIViewController *)viewController didFinishDismissWithImage:(UIImage *)image;

@end
@interface ViewController : UIViewController

@property(nonatomic,weak)id<ViewControllerDelegate> delegate;

@end
