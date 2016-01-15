//
//  PulseProcessor.m
//  PandaOC
//
//  Created by Neil on 15/5/9.
//  Copyright (c) 2015年 Neil. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PulseProcessor.h"
#import <opencv2/core.hpp>
#import <opencv2/core/core_c.h>
#import <opencv2/videoio/cap_ios.h>
#import <opencv2/imgcodecs/ios.h>

#define prefix "PandaFramework:"
#define LOG(info) std::cout << prefix \
    << info << std::endl;

typedef void (^onResult) (NSInteger sym);
using namespace cv;

const double Amin = 1.45;
const double Amax = 2.8;
const double Amaxm = 4;
const int Fmin = 14;
const int Fmax = 21;

@interface PulseProcessor ()<CvVideoCameraDelegate>;

@end

@implementation PulseProcessor {
    NSInteger counter;
    std::vector<double> avgrs;
    Scalar avgrgb;
    BOOL recorded;
    NSInteger sym;
    CvVideoCamera* videoCamera;
    UIImageView* videoView;
}

- (void) turnTorchOn {
    
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if ([device hasTorch]) {
        std::cout<<"有闪光灯"<<std::endl;
        [device lockForConfiguration:nil];
        [device setTorchMode:AVCaptureTorchModeOn];  // use AVCaptureTorchModeOn to turn on
        [device unlockForConfiguration];
    } else {
        std::cout<<"没有闪光灯"<<std::endl;
    }
}

- (void) turnTorchOff {
    
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if ([device hasTorch]) {
        std::cout<<"有闪光灯"<<std::endl;
        [device lockForConfiguration:nil];
        [device setTorchMode:AVCaptureTorchModeOff];  // use AVCaptureTorchModeOff to turn off
        [device unlockForConfiguration];
    } else {
        std::cout<<"没有闪光灯"<<std::endl;
    }
}


double maxi(std::vector<double> av,int l,int r){
    double max = 0;
    for(int i=l;i<=r;i++)
        if(av[i]>max)
            max=av[i];
    return max;
}

double mini(std::vector<double> av,int l,int r){
    double min = 256;
    for(int i=l;i<=r;i++)
        if(av[i]<min)
            min=av[i];
    return min;
}

double naiveA(std::vector<double> av){
    double max,min,sum = 0, s = 0;
    double *temp = new double[av.size()-24];
    for(int i=0;i<av.size()-24;i++){
        max = *std::max_element(&av[i], &av[i+24]);
        min = *std::min_element(&av[i], &av[i+24]);
        //max=maxi(av,i,i+24);
        //min=mini(av,i,i+24);
        temp[i] = max - min;
        sum += max - min;
    }
    sum = sum / (av.size() - 24);
    for (int i = 0; i < av.size() - 24; i++) {
        s+= (temp[i]-sum)*(temp[i]-sum);
    }
    s /= av.size()-24;
    if (s > 10) {
        return 0;
    }
    return sum;
}

int naiveF(std::vector<double> av){
    int result=0;
    for(int i=2;i<av.size()-2;i++)
        if(av[i]==*std::max_element(&av[i-2], &av[i+2]))
            result++;
    return result;
}

std::vector<double> smooth(std::vector<double> data)
{
    std::vector<double> result(data.size());
    result[0] = data[0];
    result[1] = (data[0] + data[1] + data[2])/3;
    for(int i = 2; i < data.size()-2; i++){
        result[i] = (data[i-2] + data[i-1] + data[i] + data[i+1] + data[i+2])/5;
    }
    result[data.size()-2] = (data[data.size()-3] + data[data.size()-2] + data[data.size()-1])/3;
    result[data.size()-1] = data[data.size()-1];
    return result;
}

int judge(std::vector<double> data)
{
    double A = naiveA(data);
    int F = naiveF(data);
    if (A == 0) {
        return 0;
    }
    if (F >= Fmin && F <= Fmax) {
        if (A < Amin) {
            return 1;
        } else if (A > Amax) {
            return 2;
        } else {
            return 3;
        }
    }
    if (F < Fmin) {
        if (A < Amax) {
            return 1;
        } else if (A > Amaxm) {
            return 2;
        } else {
            return 3;
        }
    }
    if (F > Fmax) {
        if (A > Amin) {
            return 2;
        } else {
            return 3;
        }
    }
    return 0;
}

- (id) init:(UIImageView*) imageView {
    self = [super init];
    
    videoCamera = [[CvVideoCamera alloc] initWithParentView:imageView];
    videoView = imageView;
    videoCamera.delegate = self;
    videoCamera.defaultAVCaptureDevicePosition = AVCaptureDevicePositionBack;
    
    [self reset];
    return self;
}

- (void) reset {
    if(self != nil){
        counter = 0;
        avgrgb = Scalar(0, 0, 0, 0);
        avgrs.clear();
        recorded = false;
        sym = 0;
    }
}

- (void) processImage:(cv::Mat &)image {
    [self process:image];
    videoView.image = MatToUIImage(image);
}

- (NSInteger) sym {
    return sym;
}

- (double) process: (Mat) mRgba {
    if (recorded) {
        cv::Rect rect = cv::Rect(0,0,mRgba.cols/3, mRgba.rows);
        mRgba = mRgba(rect);
        avgrgb = mean(mRgba);
        avgrs.push_back(avgrgb.val[2]);
        std::cout << avgrgb.val[2] << std::endl;
        counter++;
//        if (counter == 300) {
//            recorded = false;
//            sym = judge(smooth(avgrs));
//        }
        switch (counter) {
            case 1: case 2:
                return avgrs[0];
                break;
            case 3: case 4:
                return (avgrs[0] + avgrs[1] + avgrs[2]) / 3;
                break;
            default:
                return (avgrs[counter-5] + avgrs[counter-4] + avgrs[counter-3]  + avgrs[counter-2] + avgrs[counter-1] ) / 5;
                break;
        }
    }
    else {
        return 0;
    }
}

- (void) prepareRecord {
    if (recorded) {
        LOG("already started!");
        return;
    }
    [self reset];
    [self turnTorchOn];
    [videoCamera start];
}

- (void) startRecord{
    if (recorded) {
        LOG("already started!");
        return;
    }
    recorded = true;
}

- (void) finishRecord: (onResult)callback {
    if (recorded) {
        [videoCamera stop];
        [self turnTorchOff];
        recorded = false;
        sym = judge(smooth(avgrs));
        callback((int)sym);
    } else {
        LOG("it hasn't started!");
        callback(-1);
    }
}
@end
