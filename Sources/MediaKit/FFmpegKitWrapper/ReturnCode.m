/*
 * Copyright (c) 2021, 2026 Taner Sener
 *
 * This file is part of FFmpegKitNext.
 *
 * FFmpegKitNext is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * FFmpegKitNext is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General License for more details.
 *
 * You should have received a copy of the GNU Lesser General License
 * along with FFmpegKitNext. If not, see <http://www.gnu.org/licenses/>.
 */

#import "ReturnCode.h"

@implementation ReturnCode {
    int _value;
}

- (instancetype)init:(int)value {
    self = [super init];
    if (self) {
        _value = value;
    }

    return self;
}

+ (BOOL)isSuccess:(ReturnCode *)value {
    return (value != nil) && ([value getValue] == ReturnCodeSuccess);
}

+ (BOOL)isCancel:(ReturnCode *)value {
    return (value != nil) && ([value getValue] == ReturnCodeCancel);
}

- (int)getValue {
    return _value;
}

- (BOOL)isValueSuccess {
    return (_value == ReturnCodeSuccess);
}

- (BOOL)isValueError {
    return ((_value != ReturnCodeSuccess) && (_value != ReturnCodeCancel));
}

- (BOOL)isValueCancel {
    return (_value == ReturnCodeCancel);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%d", _value];
}

@end
