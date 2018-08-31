//
//  PlayMusicViewController.m
//  SJAudioPlayerDemo
//
//  Created by 张诗健 on 2017/4/3.
//  Copyright © 2017年 张诗健. All rights reserved.
//

#import "PlayMusicViewController.h"
#import "SJAudioPlayer/SJAudioPlayer.h"
#import "SDWebImage/UIImageView+WebCache.h"


@interface PlayMusicViewController ()<SJAudioPlayerDelegate>

@property (weak, nonatomic) IBOutlet UIImageView *backgroundImageView;

@property (weak, nonatomic) IBOutlet UILabel *titleLabel;

@property (weak, nonatomic) IBOutlet UIImageView *musiceImageView;

@property (weak, nonatomic) IBOutlet UILabel *musicNameLabel;

@property (weak, nonatomic) IBOutlet UILabel *artistLabel;

@property (weak, nonatomic) IBOutlet UIProgressView *progressView;

@property (weak, nonatomic) IBOutlet UISlider *slider;

@property (weak, nonatomic) IBOutlet UILabel *playedTimeLabel;

@property (weak, nonatomic) IBOutlet UILabel *durationLabel;

@property (weak, nonatomic) IBOutlet UIButton *playOrPauseButton;

@property (nonatomic, strong) SJAudioPlayer *player;

@property (nonatomic, strong) NSArray *musicList;

@property (nonatomic, strong) NSDictionary *currentMusicInfo;

@property (nonatomic, assign) NSInteger currentIndex;

@end


@implementation PlayMusicViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.titleLabel.text = @"SJAudioPlayer";
    
    
    /*
     播放本地音频文件
     
     NSString *path = [[NSBundle mainBundle] pathForResource:@"Sample" ofType:@"mp3"];
    
     NSURL *url = [NSURL fileURLWithPath:path];
    */
    
    
    
    /*
     播放远程音频文件
    */
    self.musicList = @[@{@"music_url":@"http://music.163.com/song/media/outer/url?id=166321.mp3", @"pic":@"http://imgsrc.baidu.com/forum/w=580/sign=0828c5ea79ec54e741ec1a1689399bfd/e3d9f2d3572c11df80fbf7f7612762d0f703c238.jpg", @"artist":@"毛阿敏", @"music_name":@"爱上张无忌"},
                       @{@"music_url":@"http://music.163.com/song/media/outer/url?id=27902537.mp3", @"pic":@"http://attach.bbs.miui.com/forum/201401/10/225901w011gxc00mz0gao9.jpg", @"artist":@"杨宗纬 / 叶蓓", @"music_name":@"我们好像在哪见过"},
                       @{@"music_url":@"http://music.163.com/song/media/outer/url?id=166317.mp3", @"pic":@"https://timgsa.baidu.com/timg?image&quality=80&size=b9999_10000&sec=1535729826868&di=ab3a9c6bc4fc12fcebb6a63e5dc32893&imgtype=jpg&src=http%3A%2F%2Fimg0.imgtn.bdimg.com%2Fit%2Fu%3D1503310080%2C1140367239%26fm%3D214%26gp%3D0.jpg", @"artist":@"金学峰", @"music_name":@"心爱"}];
    
    
    self.currentIndex = 0;
    self.currentMusicInfo = self.musicList.firstObject;
    
    NSURL *url = [NSURL URLWithString:self.currentMusicInfo[@"music_url"]];
    
    self.player = [[SJAudioPlayer alloc] initWithUrl:url];
    
    self.player.delegate = self;
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateProgress) userInfo:nil repeats:YES];
}

- (void)updateProgress
{
    self.durationLabel.text   = [self timeIntervalToMMSSFormat:self.player.duration];
    self.playedTimeLabel.text = [self timeIntervalToMMSSFormat:self.player.progress];
    
    if (self.player.duration > 0.0)
    {
        self.slider.value = self.player.progress/self.player.duration;
    }else
    {
        self.slider.value = 0.0;
    }
}


- (IBAction)showMusicList:(id)sender
{
    
}


- (IBAction)likeTheMusic:(UIButton *)sender
{
    sender.selected = !sender.selected;
}


- (IBAction)changePlaySequence:(id)sender
{
    
}


- (IBAction)lastMusic:(id)sender
{
    self.currentIndex--;
    
    if (self.currentIndex < 0)
    {
        self.currentIndex = self.musicList.count - 1;
    }
    
    self.currentMusicInfo = self.musicList[self.currentIndex];
    
    [self.player stop];
    
    NSURL *url = [NSURL URLWithString:self.currentMusicInfo[@"music_url"]];
    
    self.player = [[SJAudioPlayer alloc] initWithUrl:url];
    
    self.player.delegate = self;
    
    [self.player play];
}


- (IBAction)nextMusic:(id)sender
{
    self.currentIndex++;
    
    if (self.currentIndex >= self.musicList.count)
    {
        self.currentIndex = 0;
    }
    
    self.currentMusicInfo = self.musicList[self.currentIndex];
    
    [self.player stop];
    
    NSURL *url = [NSURL URLWithString:self.currentMusicInfo[@"music_url"]];
    
    self.player = [[SJAudioPlayer alloc] initWithUrl:url];
    
    self.player.delegate = self;
    
    [self.player play];
}


- (IBAction)playOrPause:(UIButton *)sender
{
    if ([self.player isPlaying])
    {
        [self.player pause];
        
        sender.selected = NO;
    }else
    {
        [self.player play];
        
        sender.selected = YES;
    }
}


- (IBAction)seek:(UISlider *)sender
{
    [self.player seekToProgress:(sender.value * self.player.duration)];
}



- (void)setCurrentMusicInfo:(NSDictionary *)currentMusicInfo
{
    _currentMusicInfo = currentMusicInfo;
    
    self.musicNameLabel.text = currentMusicInfo[@"music_name"];
    self.artistLabel.text    = currentMusicInfo[@"artist"];
    
    CATransition *transition  = [CATransition animation];
    transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    transition.duration = 0.2;
    transition.type     = kCATransitionFade;
    
    [self.musiceImageView.layer addAnimation:transition forKey:@"fade"];
    
    __weak typeof(self) weakself = self;
    
    [self.musiceImageView sd_setImageWithURL:[NSURL URLWithString:currentMusicInfo[@"pic"]] placeholderImage:[UIImage imageNamed:@"music_placeholder"] completed:^(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL) {
        
        __strong typeof(weakself) strongself = weakself;
        
        strongself.backgroundImageView.image = image;
    }];
}


- (NSString *)timeIntervalToMMSSFormat:(NSTimeInterval)interval
{
    NSInteger ti = (NSInteger)interval;
    NSInteger seconds = ti % 60;
    NSInteger minutes = (ti / 60) % 60;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
}


#pragma mark- SJAudioPlayerDelegate
- (void)audioPlayer:(SJAudioPlayer *)audioPlayer updateAudioDownloadPercentage:(float)percentage
{
    self.progressView.progress = percentage;
}

- (void)audioPlayer:(SJAudioPlayer *)audioPlayer statusDidChanged:(SJAudioPlayerStatus)status
{
    switch (status)
    {
        case SJAudioPlayerStatusIdle:
        {
            NSLog(@"SJAudioPlayerStatusIdle");
            self.playOrPauseButton.selected = NO;
        }
            break;
        case SJAudioPlayerStatusWaiting:
        {
            NSLog(@"SJAudioPlayerStatusWaiting");
        }
            break;
        case SJAudioPlayerStatusPlaying:
        {
            NSLog(@"SJAudioPlayerStatusPlaying");
            self.playOrPauseButton.selected = YES;
        }
            break;
        case SJAudioPlayerStatusPaused:
        {
            NSLog(@"SJAudioPlayerStatusPaused");
            self.playOrPauseButton.selected = NO;
        }
            break;
        case SJAudioPlayerStatusFinished:
        {
            NSLog(@"SJAudioPlayerStatusFinished");
            
            [self nextMusic:nil];
        }
            break;
        default:
            break;
    }
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
