//
//  SPImage.m
//  CocoaLibSpotify
//
//  Created by Daniel Kennett on 2/20/11.
/*
Copyright (c) 2011, Spotify AB
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Spotify AB nor the names of its contributors may 
      be used to endorse or promote products derived from this software 
      without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL SPOTIFY AB BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT 
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, 
OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "SPImage.h"
#import "SPSession.h"
#import "SPURLExtensions.h"

@interface SPImage ()

-(void) cacheSpotifyURL;

@property (nonatomic, readwrite) const byte *imageId;
@property (nonatomic, readwrite, strong) SPPlatformNativeImage *image;
@property (nonatomic, readwrite) sp_image *spImage;
@property (nonatomic, readwrite, getter=isLoaded) BOOL loaded;
@property (nonatomic, readwrite) __unsafe_unretained SPSession *session;
@property (nonatomic, readwrite, copy) NSURL *spotifyURL;

@end

static void image_loaded(sp_image *image, void *userdata) {
    [(__bridge SPImage *)userdata setLoaded:sp_image_is_loaded(image)];
}

static NSString * const kSPImageKVOContext = @"kSPImageKVOContext";

@implementation SPImage {
	BOOL hasRequestedImage;
	SPPlatformNativeImage *_image;
}

static NSMutableDictionary *imageCache;

+(SPImage *)imageWithImageId:(const byte *)imageId inSession:(SPSession *)aSession {

    if (imageCache == nil) {
        imageCache = [[NSMutableDictionary alloc] init];
    }
    
	if (imageId == NULL) {
		return nil;
	}
	
	NSData *imageIdAsData = [NSData dataWithBytes:imageId length:SPImageIdLength];
	SPImage *cachedImage = [imageCache objectForKey:imageIdAsData];
	
	if (cachedImage != nil)
		return cachedImage;
	
	cachedImage = [[SPImage alloc] initWithImageStruct:NULL
											   imageId:imageId
											 inSession:aSession];
	[imageCache setObject:cachedImage forKey:imageIdAsData];
	return cachedImage;
}

+(SPImage *)imageWithImageURL:(NSURL *)imageURL inSession:(SPSession *)aSession {
	
	if ([imageURL spotifyLinkType] == SP_LINKTYPE_IMAGE) {
		sp_link *link = [imageURL createSpotifyLink];
		sp_image *image = sp_image_create_from_link(aSession.session, link);
		
		if (link != NULL)
			sp_link_release(link);
		
		if (image != NULL) {
			SPImage *spImage = [self imageWithImageId:sp_image_image_id(image) inSession:aSession];
			sp_image_release(image);	
			return spImage;
		}
	}
	return nil;
}

#pragma mark -

-(id)initWithImageStruct:(sp_image *)anImage imageId:(const byte *)anId inSession:aSession {
	
    if ((self = [super init])) {
		
		self.session = aSession;
		self.imageId = anId;
        
        [self addObserver:self
               forKeyPath:@"loaded"
                  options:0
                  context:(__bridge void *)kSPImageKVOContext];
		
		if (anImage != NULL) {
			self.spImage = anImage;
			sp_image_add_ref(self.spImage);
			sp_image_add_load_callback(self.spImage,
									   &image_loaded,
									   (__bridge void *)(self));
			
			[self cacheSpotifyURL];
        
			self.loaded = sp_image_is_loaded(self.spImage);
        }
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == (__bridge void *)kSPImageKVOContext) {
        if ([keyPath isEqualToString:@"loaded"] && [self isLoaded] && ([self image] == nil)) {
            if (sp_image_format(self.spImage) == SP_IMAGE_FORMAT_JPEG) {
                
                size_t size;
                const byte *data = sp_image_data(self.spImage, &size);
                
                if (size > 0) {
                    NSData *imageData = [NSData dataWithBytes:data length:size];
                    [self setImage:[[SPPlatformNativeImage alloc] initWithData:imageData]];
                }
            }
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@synthesize spImage;
@synthesize loaded;
@synthesize session;
@synthesize spotifyURL;
@synthesize imageId;

-(SPPlatformNativeImage *)image {
	if (self.spImage == nil && !hasRequestedImage)
		[self beginLoading];
	return _image;
}

-(void)setImage:(SPPlatformNativeImage *)anImage {
	if (_image != anImage) {
		_image = anImage;
	}
}

#pragma mark -

-(void)beginLoading {
	
	if (self.spImage != NULL)
		return;
	
	[self willChangeValueForKey:@"spImage"];
	sp_image *newImage = sp_image_create(self.session.session, self.imageId);
	spImage = newImage;
	[self didChangeValueForKey:@"spImage"];
	
	if (spImage != NULL) {
        [self cacheSpotifyURL];
        
		hasRequestedImage = YES;
		sp_image_add_load_callback(spImage, &image_loaded, (__bridge void *)(self));
		self.loaded = sp_image_is_loaded(spImage);
	}
}

-(void)dealloc {
    
    [self removeObserver:self forKeyPath:@"loaded"];
    
    sp_image_remove_load_callback(self.spImage, &image_loaded, (__bridge void *)(self));
    sp_image_release(self.spImage);
    
}

-(void) cacheSpotifyURL
{
    if (self.spotifyURL != NULL)
        return;
    
    sp_link *link = sp_link_create_from_image(self.spImage);
    
    if (link != NULL) {
        NSURL *url = [NSURL urlWithSpotifyLink:link];
        self.spotifyURL = url;
        sp_link_release(link);
    }
}

@end
