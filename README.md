# Novi

小红书主界面的 SwiftUI 复刻。iOS 17+，纯前端，没有网络请求。

```
ios/
├── project.yml                 xcodegen 工程定义
└── Novi/
    ├── App/                    入口、根 TabView、自绘底栏、demo 启动参数
    ├── Design/NV.swift         全部颜色 / 间距 / 字号
    ├── Model/                  数据结构 + 全部假数据
    ├── Components/             瀑布流、自动换行 Layout、程序化生成的图
    └── Features/               首页 · 笔记详情 · 市集 · 消息 · 我 · 发布
```

## 跑起来

```bash
brew install xcodegen                     # 只需一次
cd ios && xcodegen generate
xcodebuild -project Novi.xcodeproj -scheme Novi \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build build
```

`xcodegen` 是必需的：工程用显式文件引用，新加的 `.swift` 在重新 generate 之前
对构建是不存在的。

## demo 启动参数

`simctl` 能启动和截图，但不能点。所以每一屏都能用启动参数直达 —— 否则藏在三次
点击后面的界面就没人真正看过。

```bash
xcrun simctl launch <UDID> com.novi.app \
  -demoTab market|messages|me       # 直接打开某个底栏 tab
  -demoLane following|nearby        # 首页停在 关注 / 同城
  -demoNote n5                      # 直接推进某条笔记详情（first = 第一条）
  -demoPublish YES                  # 打开发布面板
```

## 几个不是随手写的决定

**封面图是画出来的，不是拉下来的。** 一个照片流的复刻背后没有照片，诚实的选项
只有灰方块和生成图。灰方块读起来就是加载失败 —— 参考截图里真实的小红书正好卡在
那个状态 —— 而且一整屏灰方块说明不了任何布局问题。每张封面是笔记 id 的确定性
函数：同一条笔记在任何设备任何一次启动都画出同一张图，瀑布流才是稳定的网格而不是
噪声。`GeneratedArt.swift` 里没有 `Date()` 也没有 `random()`，否则每一帧滚动都会
重掷一次。

**瀑布流不是 `LazyVGrid`。** grid 会对齐行，矮卡片挨着高卡片就留一道空，封面不再
齐平。瀑布流没有"行"，每列各自堆叠，下一张去墨最少的那列 —— 代价是布局必须在放置
之前就知道卡片会有多高，所以 `Waterfall` 要调用方给高度估算，而不是自己量。量完再
调整会让卡片在滚动中换列。

**估算里的标题行数用 `boundingRect`，不是按字数除宽度。** 「无 SSN F-1 签证被批准
了 6000usd 额度」这种中英数混排没有单一字宽，估错一行就是列里一道看得见的台阶。

**`NoteCard.height` 必须和 body 对得上。** 量得比画得高，列里留空；矮了，两列会
错开。改动其中一个就要改另一个。

**红色只有一个位置能出现**：选中态下划线、发布按钮、角标、点亮的心。加第二个强调色，
整个"一片中性里一点红"的观感就没了。

**底栏是文字不是图标。** 这是这条 bar 最容易认出来的地方，也是真决定而不是省事：
五个图标要学，五个词是读。代价是这条 bar 没法再压缩，所以发布键是上面唯一的形状。

**`RootView` 不订阅任何会在导航过程中变化的东西。** 底栏的显隐标记放在单独的
`Chrome` 对象上，`RootView` 用 `@State` 持有（引用类型走 `@State` 只存不订阅），
只有 `TabBar` 用 `@ObservedObject` 观察它。根视图 body 一旦重跑，嵌套导航栈里
已经推进去的页面会被拆掉。

**不透明度为 0 的视图照样接触摸**，不是 UIKit 的 `alpha: 0`。底栏隐藏时同时给了
`allowsHitTesting(false)`。

**发布面板明说没接后端。** 一个看起来会动、实际什么都不做的控件，会让人怀疑屏幕
上其余部分也是假的。

## 还没做

- 搜索、笔记的作者主页、聊天详情页都还是入口没有页面
- 个人页的 笔记/收藏/赞过 切换没有吸顶
- 全部内容是假数据，没有任何网络层
