#import "YTLProbeViewController.h"
#import "../HostAdapter/YTLCaptionProbe.h"

#ifndef YTL_VERSION
#define YTL_VERSION "dev"
#endif

@implementation YTLProbeViewController {
    YTLProbeReport *_report;
}

- (instancetype)initWithReport:(YTLProbeReport *)report {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _report = report;
        self.title = [NSString stringWithFormat:@"YTLanguage v%s", YTL_VERSION];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.editable = NO;
    textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    textView.text = _report.summary;
    [self.view addSubview:textView];

    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share:)];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)share:(UIBarButtonItem *)sender {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:_report.fileName]];
    NSError *error = nil;
    if (![_report.full writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Export failed" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:activity animated:YES completion:nil];
}

@end
