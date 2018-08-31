//
//  SJAudioPlayer.m
//  SJAudioPlayer
//
//  Created by 张诗健 on 16/4/29.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJAudioPlayer.h"
#import <pthread.h>
#import <AVFoundation/AVFoundation.h>
#import "SJAudioStream.h"
#import "SJAudioFileStream.h"
#import "SJAudioQueue.h"


static UInt32 const kDefaultBufferSize = 4096;

@interface SJAudioPlayer ()<SJAudioFileStreamDelegate, SJAudioStreamDelegate>
{
    pthread_mutex_t _mutex;
    pthread_cond_t  _cond;
}

@property (nonatomic, strong) NSURL *url;

@property (nonatomic, strong) SJAudioStream *audioStream;

@property (nonatomic, strong) NSFileHandle *fileHandle;

@property (nonatomic, strong) SJAudioFileStream *audioFileStream;

@property (nonatomic, strong) SJAudioQueue *audioQueue;

@property (nonatomic, assign) SJAudioPlayerStatus status;

@property (nonatomic, assign) BOOL started;

@property (nonatomic, assign) BOOL isEof;

@property (nonatomic, assign) BOOL readDataFormLocalFile;

@property (nonatomic, assign) BOOL pausedByInterrupt;

@property (nonatomic, assign) BOOL stopRequired;

@property (nonatomic, assign) BOOL seekRequired;

@property (nonatomic, assign) BOOL pauseRequired;

@property (nonatomic, assign) BOOL finishedDownload;

@property (nonatomic, assign) SInt64 byteOffset;

@property (nonatomic, assign) NSTimeInterval seekTime;

@property (nonatomic, assign) NSTimeInterval timingOffset;

@property (nonatomic, assign) NSTimeInterval duration;

@property (nonatomic, assign) NSTimeInterval progress;

@property (nonatomic, strong) NSMutableData *audioData;

@property (nonatomic, assign) unsigned long long contentLength;

@property (nonatomic, assign) unsigned long long didDownloadLength;

@end



@implementation SJAudioPlayer


- (void)dealloc
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
}


- (instancetype)initWithUrl:(NSURL *)url
{
    NSAssert(url, @"SJAudioPlayer: url should be not nil.");
    
    self = [super init];
    
    if (self)
    {
        self.started = NO;
        self.url     = url;
        
        self.readDataFormLocalFile = [self.url isFileURL];
        
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_cond, NULL);
    }
    
    return self;
}


#pragma mark - Methods
- (void)play
{
    if (self.started)
    {
        [self resume];
    }else
    {
        // 监听中断事件
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterreption:) name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
        
        NSError *error = nil;
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
        
        if (error)
        {
            if (DEBUG)
            {
                NSLog(@"SJAudioPlayer: error setting audio session category! %@",error);
            }
        }else
        {
            // 激活音频会话控制
            [[AVAudioSession sharedInstance] setActive:YES error:&error];
            
            if (error)
            {
                if (DEBUG)
                {
                    NSLog(@"SJAudioPlayer: error setting audio session active! %@", error);
                }
            }
        }
        
        [self start];
    }
}


- (void)start
{
    self.started = YES;
    
    if (self.readDataFormLocalFile)
    {
        self.fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.url.path];
        
        self.contentLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:self.url.path error:nil] fileSize];
        
        self.didDownloadLength = self.contentLength;
        
        [self updateAudioDownloadPercentageWithDataLength:self.didDownloadLength];
        
    }else
    {
        [self startDownloadAudioData];
    }
    
    [self startPlayAudioData];
}


- (void)startDownloadAudioData
{
    NSThread *downloadThread = [[NSThread alloc] initWithTarget:self selector:@selector(downloadAudioData) object:nil];
    
    [downloadThread setName:@"com.downloadData.thread"];
    
    [downloadThread start];
}


- (void)startPlayAudioData
{
    NSThread *playAudioThread = [[NSThread alloc] initWithTarget:self selector:@selector(playAudioData) object:nil];
    
    [playAudioThread setName:@"com.playAudio.thread"];
    
    [playAudioThread start];
}


- (void)downloadAudioData
{
    self.finishedDownload = NO;
    
    BOOL done = YES;
    
    while (done && !self.finishedDownload)
    {
        if (!self.audioStream)
        {
            self.audioStream = [[SJAudioStream alloc] initWithURL:self.url byteOffset:self.byteOffset delegate:self];
        }
        
        done = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        
        [NSThread sleepForTimeInterval:0.005];
    }
}

- (void)playAudioData
{
    NSError *openAudioFileStreamError = nil;
    NSError *parseDataError = nil;
    
    self.isEof = NO;
    self.stopRequired  = NO;
    self.pauseRequired = NO;
    
    NSUInteger offset = 0;
    
    while (self.started && self.status != SJAudioPlayerStatusFinished)
    {
        @autoreleasepool
        {
            if (self.isEof)
            {
                [self.audioQueue stop:NO];
                
                [self setAudioPlayerStatus:SJAudioPlayerStatusFinished];
            }
            
            pthread_mutex_lock(&_mutex);
            
            if (self.pauseRequired)
            {
                [self.audioQueue pause:self.pausedByInterrupt];
                
                [self setAudioPlayerStatus:SJAudioPlayerStatusPaused];
                
                pthread_cond_wait(&_cond, &_mutex);
                
                if (self.stopRequired)
                {
                    [self.audioQueue stop:YES];
                    self.started = NO;
                    self.stopRequired  = NO;
                    self.pauseRequired = NO;
                    
                    [self setAudioPlayerStatus:SJAudioPlayerStatusIdle];
                    
                }else
                {
                    [self.audioQueue resume];
                    
                    self.pauseRequired = NO;
                    
                    [self setAudioPlayerStatus:SJAudioPlayerStatusPlaying];
                }
            }
            pthread_mutex_unlock(&_mutex);
            
            if (self.stopRequired)
            {
                [self.audioQueue stop:YES];
                self.started = NO;
                self.stopRequired = NO;
                
                [self setAudioPlayerStatus:SJAudioPlayerStatusIdle];
            }
            
            if (self.seekRequired)
            {
                offset = (NSUInteger)[self.audioFileStream seekToTime:&_seekTime];

                if (self.readDataFormLocalFile)
                {
                    [self.fileHandle seekToFileOffset:offset];
                }else
                {
                    if (self.finishedDownload)
                    {
                        if (offset < self.byteOffset)
                        {
                            [self.audioStream closeReadStream];

                            self.audioStream = nil;

                            [self startDownloadAudioData];
                        }
                    }else
                    {
                        self.byteOffset = offset;

                        [self.audioStream closeReadStream];

                        pthread_mutex_lock(&_mutex);
                        self.audioData = nil;
                        pthread_mutex_unlock(&_mutex);

                        self.audioStream = nil;
                    }
                }

                self.timingOffset = self.seekTime - self.audioQueue.playedTime;

                [self.audioQueue reset];
                
                self.seekRequired = NO;
            }
            
            
            NSData *data = nil;
            
            if (self.readDataFormLocalFile)
            {
                data = [self.fileHandle readDataOfLength:kDefaultBufferSize];

                offset += [data length];

                if (offset >= self.contentLength)
                {
                    self.isEof = YES;
                }
                
            }else
            {
                pthread_mutex_lock(&_mutex);
                if (self.audioData.length < (offset + kDefaultBufferSize))
                {
                    if (self.finishedDownload)
                    {
                        NSUInteger location = offset - (NSUInteger)self.byteOffset;
                        
                        data = [self.audioData subdataWithRange:NSMakeRange(location, self.audioData.length - location)];
                        
                        self.isEof = YES;
                    }else
                    {
                        [self setAudioPlayerStatus:SJAudioPlayerStatusWaiting];
                        
                        pthread_cond_wait(&_cond, &_mutex);
                        
                        [self setAudioPlayerStatus:SJAudioPlayerStatusPlaying];
                    }
                }else
                {
                    NSUInteger location = offset - (NSUInteger)self.byteOffset;
                    
                    data = [self.audioData subdataWithRange:NSMakeRange(location, kDefaultBufferSize)];
                }
                pthread_mutex_unlock(&_mutex);
                
                offset += [data length];
            }
            
            if (data.length)
            {
                if (!self.audioFileStream)
                {
                    if (!self.readDataFormLocalFile)
                    {
                        self.contentLength = self.audioStream.contentLength;
                    }
                    
                    self.audioFileStream = [[SJAudioFileStream alloc] initWithFileType:[self getAudioFileTypeIdForFileExtension:self.url.pathExtension] fileSize:self.contentLength error:&openAudioFileStreamError];
                    
                    if (openAudioFileStreamError)
                    {
                        if (DEBUG)
                        {
                            NSLog(@"SJAudioFileStream: failed to open AudioFileStream.");
                        }
                    }
                    
                    self.audioFileStream.delegate = self;
                }
                
                [self.audioFileStream parseData:data error:&parseDataError];
                
                if (parseDataError)
                {
                    if (DEBUG)
                    {
                        NSLog(@"SJAudioFileStream: failed to parse audio data.");
                    }
                }
            }
        }
    }
    
    [self cleanUp];
}


- (void)cleanUp
{
    self.started       = NO;
    self.stopRequired  = NO;
    self.pauseRequired = NO;
    self.seekRequired  = NO;
    self.pausedByInterrupt = NO;
    
    self.audioData  = nil;
    
    [self.audioQueue disposeAudioQueue];
    self.audioQueue = nil;
    
    [self.fileHandle closeFile];
    self.fileHandle = nil;
    
    [self.audioStream closeReadStream];
    self.audioStream = nil;
    
    [self.audioFileStream close];
    self.audioFileStream = nil;
    
    self.byteOffset        = 0;
    self.duration          = 0.0;
    self.timingOffset      = 0.0;
    self.seekTime          = 0.0;
    self.contentLength     = 0;
    self.didDownloadLength = 0;
    
    [self setAudioPlayerStatus:SJAudioPlayerStatusIdle];
    
    [self updateAudioDownloadPercentageWithDataLength:0.0];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
}


- (void)pause
{
    pthread_mutex_lock(&_mutex);
    if (!self.pauseRequired)
    {
        self.pauseRequired = YES;
    }
    pthread_mutex_unlock(&_mutex);
}


- (void)resume
{
    pthread_mutex_lock(&_mutex);
    if (self.pauseRequired && self.status != SJAudioPlayerStatusWaiting )
    {
        pthread_cond_signal(&_cond);
    }
    pthread_mutex_unlock(&_mutex);
}


- (void)stop
{
    pthread_mutex_lock(&_mutex);
    if (!self.stopRequired)
    {
        self.stopRequired = YES;
        
        if (self.pauseRequired)
        {
            pthread_cond_signal(&_cond);
        }
    }
    pthread_mutex_unlock(&_mutex);
}


- (void)seekToProgress:(NSTimeInterval)progress
{
    self.seekTime = progress;
    
    self.seekRequired = YES;
}


- (NSTimeInterval)progress
{
    if (self.seekRequired)
    {
        return self.seekTime;
    }
    return self.timingOffset + self.audioQueue.playedTime;
}

- (BOOL)isPlaying
{
    return (self.status == SJAudioPlayerStatusPlaying);
}


- (AudioFileTypeID)getAudioFileTypeIdForFileExtension:(NSString *)fileExtension
{
    AudioFileTypeID fileTypeHint = 0;
    
    if ([fileExtension isEqualToString:@"mp3"])
    {
        fileTypeHint = kAudioFileMP3Type;
        
    }else if ([fileExtension isEqualToString:@"wav"])
    {
        fileTypeHint = kAudioFileWAVEType;
        
    }else if ([fileExtension isEqualToString:@"aifc"])
    {
        fileTypeHint = kAudioFileAIFCType;
        
    }else if ([fileExtension isEqualToString:@"aiff"])
    {
        fileTypeHint = kAudioFileAIFFType;
        
    }else if ([fileExtension isEqualToString:@"m4a"])
    {
        fileTypeHint = kAudioFileM4AType;
        
    }else if ([fileExtension isEqualToString:@"mp4"])
    {
        fileTypeHint = kAudioFileMPEG4Type;
        
    }else if ([fileExtension isEqualToString:@"caf"])
    {
        fileTypeHint = kAudioFileCAFType;
        
    }else if ([fileExtension isEqualToString:@"aac"])
    {
        fileTypeHint = kAudioFileAAC_ADTSType;
    }
    
    return fileTypeHint;
}


- (void)updateAudioDownloadPercentageWithDataLength:(unsigned long long)dataLength
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(audioPlayer:updateAudioDownloadPercentage:)])
    {
        float percentage = 0.0;
        
        if (self.contentLength > 0)
        {
            float length = dataLength;
            
            percentage = length / self.contentLength;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self.delegate audioPlayer:self updateAudioDownloadPercentage:percentage];
        });
    }
}


- (void)setAudioPlayerStatus:(SJAudioPlayerStatus)status
{
    if (self.status == status)
    {
        return;
    }
    
    self.status = status;
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(audioPlayer:statusDidChanged:)])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self.delegate audioPlayer:self statusDidChanged:status];
        });
    }
}


#pragma mark- SJAudioStreamDelegate
- (void)audioStreamHasBytesAvailable:(SJAudioStream *)audioStream
{
    if (self.audioData == nil)
    {
        self.audioData = [[NSMutableData alloc] init];
        
        self.didDownloadLength += self.byteOffset;
    }
    
    NSError *readDataError = nil;
    
    // 每次读取 20KB 的数据（长度太小，`audioStreamHasBytesAvailable`方法调用次数太频繁，会导致CPU占用率过高）
    NSData *data = [self.audioStream readDataWithMaxLength:(kDefaultBufferSize * 5) error:&readDataError];
    
    if (readDataError)
    {
        if (DEBUG)
        {
            NSLog(@"SJAudioFileStream: failed to read data.");
        }
    }
    
    self.didDownloadLength += [data length];
    
    [self updateAudioDownloadPercentageWithDataLength:self.didDownloadLength];
    
    pthread_mutex_lock(&_mutex);
    [self.audioData appendData:data];
    if (self.audioData.length >= kDefaultBufferSize)
    {
        if (!self.pauseRequired)
        {
            pthread_cond_signal(&_cond);
        }
    }
    pthread_mutex_unlock(&_mutex);
}

- (void)audioStreamEndEncountered:(SJAudioStream *)audioStream
{
    self.finishedDownload = YES;
}

- (void)audioStreamErrorOccurred:(SJAudioStream *)audioStream
{
    [self.audioStream closeReadStream];
    
    [NSThread sleepForTimeInterval:1.0];
    
    self.audioStream = [[SJAudioStream alloc] initWithURL:self.url byteOffset:self.audioData.length delegate:self];;
    
    if (DEBUG)
    {
        NSLog(@"SJAudioStream: error occurred.");
    }
}

#pragma mark- SJAudioFileStreamDelegate
- (void)audioFileStream:(SJAudioFileStream *)audioFileStream receiveInputData:(const void *)inputData numberOfBytes:(UInt32)numberOfBytes numberOfPackets:(UInt32)numberOfPackets packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions
{
    BOOL success = [self.audioQueue playData:[NSData dataWithBytes:inputData length:numberOfBytes] packetCount:numberOfPackets packetDescriptions:packetDescriptions isEof:self.isEof];
    
    if (!success)
    {
        if (DEBUG)
        {
            NSLog(@"SJAudioQueue: failed to play packet data.");
        }
    }
}


- (void)audioFileStreamReadyToProducePackets:(SJAudioFileStream *)audioFileStream
{
    NSData *magicCookie = [self.audioFileStream getMagicCookieData];
    
    AudioStreamBasicDescription format = self.audioFileStream.format;
    
    self.audioQueue = [[SJAudioQueue alloc] initWithFormat:format bufferSize:kDefaultBufferSize macgicCookie:magicCookie];
    
    self.duration = self.audioFileStream.duration;
}


#pragma mark- AVAudioSessionInterruptionNotification
- (void)handleInterreption:(NSNotification *)notification
{
    AVAudioSessionInterruptionType interruptionType = [[[notification userInfo] objectForKey:AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    
    if (interruptionType == AVAudioSessionInterruptionTypeBegan)
    {
        if (self.status == SJAudioPlayerStatusPlaying)
        {
            self.pausedByInterrupt = YES;
            
            [self pause];
        }
    }else if (interruptionType == AVAudioSessionInterruptionTypeEnded)
    {
        NSError *error = nil;
        
        [[AVAudioSession sharedInstance] setActive:YES error:&error];
        
        if (error)
        {
            if (DEBUG)
            {
                NSLog(@"SJAudioPlayer: Error setting audio session active! %@", error);
            }
        }
        
        if (self.status == SJAudioPlayerStatusPaused && self.pausedByInterrupt)
        {
            [self resume];
            
            self.pausedByInterrupt = NO;
        }
    }
}

@end

