//
//  main.m
//  PanicButton
//
//  Created by Alex C. Schaefer on 2/10/13.
//  Copyright (c) 2013 AlexRocks. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <IOKit/IOTypes.h>
#import <IOKit/IOReturn.h>
#import <IOKit/hid/IOHIDLib.h>
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/hid/IOHIDKeys.h>

#define kPanicButtonVendorID 4400
#define kPanicButtonPrimaryUsage 0
#define kPanicButtonProductName "Panic Button"

static void PanicButtonTimerCallback(CFRunLoopTimerRef timer, void *info)
{
    if (NULL == info) {
        return;
    }
    
    
    IOHIDDeviceRef device = (IOHIDDeviceRef)info;
    
    CFIndex reportLen = 8;  //If this isn't 8, IOKit freaks the hell out
    uint8_t *reportFromDevice = calloc(sizeof(uint8_t), reportLen);
    
    //This will get the latest status of the device.  Basically, the last time it sent data, as best as I can tell.
    IOReturn deviceReportStatus = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, reportFromDevice, &reportLen);
    
    //If the report isn't a success, I don't care what is contained in data.
    if (deviceReportStatus != kIOReturnSuccess) {
        goto BAIL;
    }
    
    //Device report was obtained correctly.  Let's see what's in data[0]. If it's 1, the button has been hit.  If it's a 0, the button has not been hit.  That sounds familiar.
    if (!reportFromDevice[0]) {
        goto BAIL;
    }
    
    NSLog(@"PANIC BUTTON HAS BEEN HIT.  HOLY SHIT.");
    
    BAIL: {
        free(reportFromDevice);
        reportFromDevice = NULL;
    }
}

static void HIDDeviceRemovedCallback(void *context, IOReturn result, void *sender)
{
    if (NULL == context) {
        return;
    }
    
    CFRunLoopTimerRef timer = (CFRunLoopTimerRef)context;
    CFRunLoopTimerContext deviceContext = {0};
    CFRunLoopTimerGetContext(timer, &deviceContext);

    //Device context contains the IOHIDDeviceRef, which we retained when we added it to the runloop timer context
    if (NULL != deviceContext.info && IOHIDDeviceGetTypeID() == CFGetTypeID(deviceContext.info)) {
        CFRelease(deviceContext.info);
        deviceContext.info = NULL;
    }
    CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);
}

static void HIDFoundDeviceCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device)
{
    if (NULL == device) {
        return;
    }
    
    CFRunLoopTimerContext deviceContext = {0};
    deviceContext.info = (void *)CFRetain(device);
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(kCFAllocatorDefault, 0, 0.25, 0, 0, PanicButtonTimerCallback, &deviceContext); //Every quarter of a second, i will ask to see if something has changed.
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);
    IOHIDDeviceRegisterRemovalCallback(device, HIDDeviceRemovedCallback, timer);  //I want to know when the device is removed so that I can kill the timer
    CFRelease(timer);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        IOHIDManagerRef managerRef = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
        
        CFMutableDictionaryRef deviceProperties = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(deviceProperties, CFSTR(kIOHIDPrimaryUsageKey), @(kPanicButtonPrimaryUsage));
        CFDictionarySetValue(deviceProperties, CFSTR(kIOHIDVendorIDKey), @(kPanicButtonVendorID));
        CFDictionarySetValue(deviceProperties, CFSTR(kIOHIDProductKey), CFSTR(kPanicButtonProductName));

        
        //Find a button with matching properties.
        IOHIDManagerSetDeviceMatching(managerRef, deviceProperties);
        
        CFRelease(deviceProperties);
        deviceProperties = NULL;
        
        //When a device with matching properties, as declared by the above method, is found - talk to HIDFoundDeviceCallback method
        IOHIDManagerRegisterDeviceMatchingCallback(managerRef, HIDFoundDeviceCallback, NULL);
        //Make sure this scanning occurs on the run loop
        IOHIDManagerScheduleWithRunLoop(managerRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        //Opening the manager opens the flood gates -  scanning will then occur at the end of the run loop
        IOReturn managerOpenStatus = IOHIDManagerOpen(managerRef, kIOHIDOptionsTypeNone);
        if (managerOpenStatus == kIOReturnSuccess) {
            //If the manager opened correctly, we kickstart the run loop and wait for money datas to pour in
            [[NSRunLoop currentRunLoop] run];
        } else {
            NSLog(@"No dice, headlice.");
        }
        
        CFRelease(managerRef);
    }
    return 0;
}