//
//  ImageUploader.m
//  IRCCloud
//
//  Created by Sam Steele on 5/7/14.
//  Copyright (c) 2014 IRCCloud, Ltd. All rights reserved.
//

#import "ImageUploader.h"
#import "SBJson.h"
#import "NSData+Base64.h"
#import "config.h"

@implementation ImageUploader
-(void)upload:(UIImage *)img {
    _image = img;
    [self performSelectorInBackground:@selector(_upload:) withObject:img];
}

-(void)_upload:(UIImage *)img {
    NSData *data = UIImageJPEGRepresentation(img, 0.8);
    CFStringRef data_escaped = CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[data base64EncodedString], NULL, (CFStringRef)@"&+/?=[]();:^", kCFStringEncodingUTF8);
    
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.imgur.com/3/image"] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60];
    [request setHTTPShouldHandleCookies:NO];
#ifdef IMGUR_KEY
    if([[NSUserDefaults standardUserDefaults] objectForKey:@"imgur_access_token"]) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", [[NSUserDefaults standardUserDefaults] objectForKey:@"imgur_access_token"]] forHTTPHeaderField:@"Authorization"];
    } else {
        [request setValue:[NSString stringWithFormat:@"Client-ID %@", @IMGUR_KEY] forHTTPHeaderField:@"Authorization"];
    }
#endif
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[[NSString stringWithFormat:@"image=%@", data_escaped] dataUsingEncoding:NSUTF8StringEncoding]];
    
    CFRelease(data_escaped);
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        _response = [[NSMutableData alloc] init];
        _connection = [NSURLConnection connectionWithRequest:request delegate:self];
        [_connection start];
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    }];
}

-(void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite {
    if(_delegate)
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [_delegate imageUploadProgress:(float)totalBytesWritten / (float)totalBytesExpectedToWrite];
        }];
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [_response appendData:data];
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    [_delegate imageUploadDidFail];
}

-(void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    
    NSDictionary *d = [[[SBJsonParser alloc] init] objectWithData:_response];
#ifdef IMGUR_KEY
    if([[NSUserDefaults standardUserDefaults] objectForKey:@"imgur_access_token"] && [[d objectForKey:@"success"] intValue] == 0 && [[d objectForKey:@"status"] intValue] == 403) {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.imgur.com/oauth2/token"]];
        [request setHTTPMethod:@"POST"];
        [request setHTTPBody:[[NSString stringWithFormat:@"refresh_token=%@&client_id=%@&client_secret=%@&grant_type=refresh_token", [[NSUserDefaults standardUserDefaults] objectForKey:@"imgur_refresh_token"], @IMGUR_KEY, @IMGUR_SECRET] dataUsingEncoding:NSUTF8StringEncoding]];

        [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
            if (error) {
                NSLog(@"Error renewing token. Error %li : %@", (long)error.code, error.userInfo);
                [_delegate imageUploadDidFail];
            } else {
                SBJsonParser *parser = [[SBJsonParser alloc] init];
                NSDictionary *dict = [parser objectWithData:data];
                if([[dict objectForKey:@"success"] intValue] == 1)
                    [self performSelectorInBackground:@selector(_upload:) withObject:_image];
                else
                    [_delegate imageUploadNotAuthorized];
            }
        }];
        return;
    }
#endif
    [_delegate imageUploadDidFinish:d];
}
@end
