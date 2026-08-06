//
//  ViewController.m
//  demolist
//

#import "ViewController.h"
#import "AppListManager.h"

@interface ViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *apps;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"已安装应用";
    
    self.view.backgroundColor = [UIColor whiteColor];

    [self setupTableView];
    [self loadApps];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
}

- (void)loadApps {
    self.apps = [AppListManager installedApps];
    self.title = [NSString stringWithFormat:@"已安装应用 (%lu)", (unsigned long)self.apps.count];
    NSLog(@"ViewController: loaded %lu apps", (unsigned long)self.apps.count);
    for (NSDictionary *dict in self.apps) {
        NSLog(@"%@",dict);
    }
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.apps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    }

    NSDictionary *app = self.apps[indexPath.row];
    cell.textLabel.text = app[@"name"];
    cell.detailTextLabel.text = app[@"bundleID"];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    return cell;
}

@end
