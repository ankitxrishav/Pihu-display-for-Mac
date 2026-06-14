#ifndef CGVirtualDisplayPrivate_h
#define CGVirtualDisplayPrivate_h

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic, retain) dispatch_queue_t queue;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) uint32_t maxPixelsWide;
@property (nonatomic) uint32_t maxPixelsHigh;
@property (nonatomic) uint32_t productID;
@property (nonatomic) uint32_t vendorID;
@property (nonatomic) uint32_t serialNum;
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate;
@property (nonatomic, readonly) uint32_t width;
@property (nonatomic, readonly) uint32_t height;
@property (nonatomic, readonly) double refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic, copy) NSArray<CGVirtualDisplayMode *> *modes;
@property (nonatomic) uint32_t hiDPI;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
@property (nonatomic, readonly) CGDirectDisplayID displayID;
@property (nonatomic, readonly) CGVirtualDisplayDescriptor *descriptor;
@property (nonatomic, readonly) CGVirtualDisplaySettings *settings;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

#endif /* CGVirtualDisplayPrivate_h */
