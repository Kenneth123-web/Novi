import SwiftUI

/// Fixture content. Everything here is invented — it is a UI reproduction, not
/// a scrape — and it exists to exercise the layout: long titles that wrap to
/// two lines, short ones that do not, tall covers next to square ones, four
/// and five digit like counts.
enum Fixtures {

    static let me = Author(
        id: "me",
        name: "Novi 用户",
        noviID: "novi_8213904",
        bio: "记录一点点生活 · 摄影 / 咖啡 / 城市漫步",
        followers: 128,
        following: 96,
        liked: 342
    )

    static let authors: [Author] = [
        Author(id: "a1", name: "Steven_Peng", noviID: "steven_p", bio: "在纽约读书 · 签证 / 信用卡 / 生活", followers: 12_400, following: 210, liked: 38_900),
        Author(id: "a2", name: "瓜师傅", noviID: "guashifu", bio: "每天一个不太靠谱的科技瓜", followers: 86_300, following: 42, liked: 512_000),
        Author(id: "a3", name: "吃了一块鸡蛋饼", noviID: "eggpancake", bio: "记账 / 踩坑 / 反省", followers: 3_120, following: 380, liked: 9_800),
        Author(id: "a4", name: "Lucky", noviID: "lucky_0", bio: "跨境小白日记", followers: 640, following: 120, liked: 1_900),
        Author(id: "a5", name: "阿吱", noviID: "azhi_", bio: "杭州 · 拍照的人", followers: 24_800, following: 156, liked: 96_400),
        Author(id: "a6", name: "林一口", noviID: "linyikou", bio: "一个人吃饭也要好好吃", followers: 51_200, following: 88, liked: 233_000),
        Author(id: "a7", name: "momo", noviID: "momo_2333", bio: "", followers: 12, following: 301, liked: 40),
        Author(id: "a8", name: "小满不慌", noviID: "xiaoman", bio: "上班 / 下班 / 攒钱", followers: 7_800, following: 233, liked: 21_000),
        Author(id: "a9", name: "海边的卡夫卡", noviID: "kafka_sea", bio: "读书笔记 & 长句子", followers: 18_900, following: 64, liked: 72_300),
        Author(id: "a10", name: "十七", noviID: "seventeen", bio: "自习室常驻", followers: 2_400, following: 410, liked: 8_100),
        Author(id: "a11", name: "Tofu", noviID: "tofu_cook", bio: "厨房里的实验", followers: 33_600, following: 71, liked: 141_000),
        Author(id: "a12", name: "拿铁不加糖", noviID: "latte_no", bio: "咖啡因依赖症", followers: 9_600, following: 190, liked: 27_400),
    ]

    static func author(_ i: Int) -> Author { authors[i % authors.count] }

    // MARK: 发现

    static let discover: [Note] = [
        Note(id: "n1", title: "无 SSN F-1 签证被批准了 6000usd 额度，有人知道为什么吗", author: author(0), likes: 20, ratio: 0.75,
             body: "上周申请的时候完全没抱希望，材料只交了 I-20 和银行流水，结果今天邮件说批了。\n\n去年同学同样条件被拒了两次，所以我也不知道到底哪一步起了作用。把我交的东西列一下，给后面的人参考。",
             tags: ["留学生活", "信用卡", "美国"], collects: 63, comments: 18, photos: 3, place: "New York", postedAt: "昨天 21:04"),

        Note(id: "n2", title: "千万不要用 GPT6-Astra！", author: author(1), likes: 231, ratio: 0.8, badge: .hot,
             body: "标题党了，但真的有话说。用了三周，写代码是真的强，但它会非常自信地把不存在的 API 讲得头头是道。\n\n昨天按它给的方法调了一个下午，最后发现那个参数从来没存在过。",
             tags: ["AI", "效率工具", "踩坑"], collects: 1_204, comments: 356, photos: 2, postedAt: "3 小时前"),

        Note(id: "n3", title: "办了 boa 押金信用卡后一直在后悔", author: author(2), likes: 48, ratio: 0.62,
             body: "押金 300 刀锁了一年，额度就是 300。真正的问题是它不自动升级，我等了 11 个月客服才说要手动打电话申请。",
             tags: ["信用卡", "省钱"], collects: 132, comments: 41, photos: 1, postedAt: "2 天前"),

        Note(id: "n4", title: "新开的 PayPal，只收了一笔款就这样了", author: author(3), likes: 7, ratio: 0.72,
             body: "账号被限制 180 天，申诉了三次都是同一个模板回复。留个记录，也许有人遇到过一样的情况。",
             tags: ["跨境", "收款"], collects: 9, comments: 6, photos: 2, postedAt: "5 小时前"),

        Note(id: "n5", title: "在杭州拍了一整天的秋天，出片率高得离谱", author: author(4), likes: 3_412, ratio: 1.33,
             body: "九溪十八涧的银杏差不多黄透了，工作日下午人真的很少。\n\n参数放在最后一张图里，全部是原相机 + 一点点曲线。",
             tags: ["摄影", "杭州", "秋天", "citywalk"], collects: 8_921, comments: 204, photos: 9, place: "杭州 · 九溪", postedAt: "1 天前"),

        Note(id: "n6", title: "一个人的深夜食堂：15 分钟葱油拌面", author: author(5), likes: 12_803, ratio: 0.75,
             body: "葱要用小葱，油温不能高，全程小火慢慢熬到葱变成焦褐色，那个香味是骗不了人的。\n\n面条我用的碱水面，比挂面耐泡。",
             tags: ["美食", "一人食", "菜谱"], collects: 34_200, comments: 891, photos: 6, postedAt: "3 天前"),

        Note(id: "n7", title: "毕业三年，我的存款曲线", author: author(7), likes: 892, ratio: 1.0,
             body: "从月光到现在，最有用的其实不是记账，是把工资一到账就转走 40%。剩下的随便花，反而没有负罪感。",
             tags: ["理财", "存钱", "打工人"], collects: 2_401, comments: 176, photos: 4, postedAt: "6 小时前"),

        Note(id: "n8", title: "这本书我读了四遍，每一遍都在不同的地方哭", author: author(8), likes: 5_640, ratio: 0.68,
             body: "第一遍在高三的晚自习，第四遍是上个月的通勤地铁上。同样一句话，二十岁和二十七岁读出来完全不是一个意思。",
             tags: ["读书", "书单"], collects: 11_030, comments: 322, photos: 2, postedAt: "4 天前"),

        Note(id: "n9", title: "自习室蹲了 200 小时，说点实话", author: author(9), likes: 431, ratio: 0.75,
             body: "付费自习室最值钱的不是环境，是沉没成本。花了钱就不好意思刷手机。",
             tags: ["考研", "自律"], collects: 980, comments: 57, photos: 3, postedAt: "昨天"),

        Note(id: "n10", title: "厨房小白第一次做舒芙蕾，塌了但很好吃", author: author(10), likes: 2_180, ratio: 1.2,
             body: "蛋白打过头了，出炉三分钟就塌成一张饼。味道其实没差，只是拍不出网上那种高度。",
             tags: ["烘焙", "翻车现场"], collects: 3_400, comments: 128, photos: 5, postedAt: "2 天前"),

        Note(id: "n11", title: "上海咖啡地图 · 第 37 家", author: author(11), likes: 764, ratio: 0.8, badge: .video,
             body: "永康路这家的手冲比想象中好，但座位真的太少了，工作日下午两点还要等位。",
             tags: ["咖啡", "上海", "探店"], collects: 1_890, comments: 63, photos: 1, place: "上海 · 永康路", postedAt: "8 小时前"),

        Note(id: "n12", title: "租房两年，我把 30 平米改成了这样", author: author(4), likes: 9_320, ratio: 0.75,
             body: "全部预算 4200，最贵的是那张桌子。房东不让打孔，所以基本都是免钉胶和撑杆。",
             tags: ["租房改造", "家居", "小户型"], collects: 28_700, comments: 512, photos: 8, postedAt: "1 周前"),

        Note(id: "n13", title: "被裁员的第 47 天", author: author(7), likes: 15_600, ratio: 0.62,
             body: "今天终于把简历改完了。写下来是因为怕自己忘记这段时间到底是怎么过来的。",
             tags: ["职场", "记录"], collects: 22_100, comments: 1_403, photos: 1, postedAt: "12 小时前"),

        Note(id: "n14", title: "三亚五天四晚，人均 2800 的真实账单", author: author(3), likes: 1_204, ratio: 1.0,
             body: "机票是提前 45 天买的，住的是海棠湾一家民宿。逐项列了账单，含踩雷的两顿饭。",
             tags: ["旅行", "三亚", "攻略"], collects: 5_600, comments: 210, photos: 9, place: "三亚", postedAt: "3 天前"),

        Note(id: "n15", title: "我妈的毛衣针法，学会了", author: author(9), likes: 328, ratio: 0.75,
             body: "教了三个晚上，终于打完一只袖子。第二只她说要我自己来。",
             tags: ["手工", "编织"], collects: 720, comments: 44, photos: 4, postedAt: "5 天前"),

        Note(id: "n16", title: "凌晨四点的城市，是另一个城市", author: author(4), likes: 6_890, ratio: 1.4,
             body: "拍完这组一共走了 14 公里。清洁工、早点摊、还在亮着的写字楼，比白天好看太多。",
             tags: ["摄影", "夜景", "citywalk"], collects: 14_200, comments: 388, photos: 12, place: "北京", postedAt: "2 天前"),
    ]

    // MARK: 关注

    static let following: [Note] = [
        Note(id: "f1", title: "今天的晚饭，简单但认真", author: author(5), likes: 402, ratio: 0.75,
             body: "两菜一汤，全部二十分钟内搞定。", tags: ["一人食"], collects: 900, comments: 31, photos: 3, postedAt: "1 小时前"),
        Note(id: "f2", title: "新镜头开箱，35mm 定焦真的是万能吗", author: author(4), likes: 1_820, ratio: 1.0, badge: .live,
             body: "用了一周，答案是：不是，但它是最不会出错的那一个。", tags: ["摄影器材"], collects: 3_200, comments: 96, photos: 6, postedAt: "4 小时前"),
        Note(id: "f3", title: "把书架重新排了一遍，按颜色", author: author(8), likes: 733, ratio: 0.66,
             body: "好看是真好看，找书是真找不到。", tags: ["家居", "读书"], collects: 1_400, comments: 58, photos: 2, postedAt: "昨天"),
        Note(id: "f4", title: "手冲参数记录 · 埃塞俄比亚 日晒", author: author(11), likes: 214, ratio: 0.8,
             body: "1:15，92 度，三段注水。这支豆子的花香在第二段最明显。", tags: ["咖啡"], collects: 520, comments: 22, photos: 2, postedAt: "昨天"),
        Note(id: "f5", title: "跑了 100 天，身体给我的反馈", author: author(9), likes: 4_120, ratio: 0.75,
             body: "体重掉了 6 斤，但更明显的是睡眠。", tags: ["跑步", "自律"], collects: 9_800, comments: 240, photos: 4, postedAt: "2 天前"),
        Note(id: "f6", title: "这个季节的菜市场", author: author(10), likes: 986, ratio: 1.25,
             body: "冬笋上了，价格还没降下来。", tags: ["菜市场", "生活"], collects: 2_100, comments: 71, photos: 7, postedAt: "3 天前"),
    ]

    // MARK: 同城

    static let nearby: [Note] = [
        Note(id: "c1", title: "步行 10 分钟的小面馆，开了 20 年", author: author(5), likes: 1_320, ratio: 0.75,
             body: "老板认得每一个老客人要不要香菜。", tags: ["探店", "面"], collects: 3_100, comments: 88, photos: 4, place: "距你 1.2km", postedAt: "今天"),
        Note(id: "c2", title: "周末市集，人比摊多", author: author(11), likes: 208, ratio: 1.0,
             body: "十点前去还能逛，十一点之后基本是在人群里挪。", tags: ["市集", "周末"], collects: 410, comments: 19, photos: 5, place: "距你 3.4km", postedAt: "今天"),
        Note(id: "c3", title: "这家理发店终于没给我剪成锅盖", author: author(7), likes: 96, ratio: 0.7,
             body: "报了三次「不要剪太短」，这次他听进去了。", tags: ["日常"], collects: 140, comments: 27, photos: 2, place: "距你 800m", postedAt: "昨天"),
        Note(id: "c4", title: "河边的落日，今天特别橘", author: author(4), likes: 2_740, ratio: 1.35,
             body: "六点十分左右，云的形状刚好。", tags: ["摄影", "日落"], collects: 6_200, comments: 104, photos: 6, place: "距你 2.1km", postedAt: "昨天"),
        Note(id: "c5", title: "小区门口新开的便利店，24 小时", author: author(3), likes: 63, ratio: 0.75,
             body: "关东煮五块钱三串，深夜加班的人有救了。", tags: ["便利店"], collects: 88, comments: 12, place: "距你 300m", postedAt: "2 天前"),
        Note(id: "c6", title: "本地人才知道的公园入口", author: author(9), likes: 512, ratio: 0.9,
             body: "东北角那个小门不用排队，走进去就是湖。", tags: ["城市", "公园"], collects: 1_030, comments: 45, photos: 3, place: "距你 5.6km", postedAt: "3 天前"),
    ]

    // MARK: 评论

    static func comments(for note: Note) -> [Comment] {
        [
            Comment(author: author(6), text: "蹲一个后续，我下周也要去申请", time: "2 小时前 · 上海", likes: 34,
                    replies: [
                        Comment(author: note.author, text: "已经更新在图 3 了，可以看看", time: "1 小时前", likes: 12, isAuthor: true)
                    ]),
            Comment(author: author(8), text: "写得好细，收藏了。想问一下这个是必须的吗，还是看情况", time: "4 小时前 · 北京", likes: 18),
            Comment(author: author(2), text: "我也遇到过一模一样的情况，最后是打电话解决的", time: "6 小时前 · 广东", likes: 9),
            Comment(author: author(10), text: "第二张图是在哪里拍的呀", time: "昨天", likes: 3),
            Comment(author: author(11), text: "谢谢分享！", time: "昨天", likes: 1),
        ]
    }

    // MARK: 消息

    static let threads: [MessageThread] = [
        MessageThread(author: author(4), preview: "那组照片的参数我发你了，f/1.8 那张是后期加的暗角", time: "12:04", unread: 2),
        MessageThread(author: author(5), preview: "面条要是买不到碱水面，用干挂面多煮 30 秒也行", time: "昨天", unread: 0),
        MessageThread(author: author(1), preview: "哈哈哈标题确实党了，但内容是真的", time: "昨天", unread: 1),
        MessageThread(author: author(8), preview: "书单整理好了，一共 12 本", time: "周三", unread: 0),
        MessageThread(author: author(11), preview: "永康路那家周末别去，等位一小时起", time: "周二", unread: 0),
        MessageThread(author: author(9), preview: "自习室的位置我帮你留了", time: "上周", unread: 0),
    ]

    // MARK: 市集

    struct Product: Identifiable, Hashable {
        let id: String
        let title: String
        let price: Int
        let sold: String
        let shop: String
        let ratio: CGFloat
        var tag: String? = nil
    }

    static let products: [Product] = [
        Product(id: "p1", title: "纯棉宽松长袖 T 恤 秋冬内搭 三色可选", price: 89, sold: "已售 2.1万", shop: "Novi 严选", ratio: 0.75, tag: "自营"),
        Product(id: "p2", title: "手冲咖啡壶套装 新手入门 含滤纸", price: 168, sold: "已售 4300", shop: "山丘咖啡器具", ratio: 1.0),
        Product(id: "p3", title: "复古黄铜台灯 卧室床头 暖光护眼", price: 249, sold: "已售 890", shop: "旧物研究所", ratio: 0.8, tag: "低价"),
        Product(id: "p4", title: "云朵抱枕 加大款 可拆洗", price: 79, sold: "已售 1.6万", shop: "软软家居", ratio: 0.72),
        Product(id: "p5", title: "帆布托特包 大容量 通勤 附内胆", price: 118, sold: "已售 7200", shop: "一只包", ratio: 1.15),
        Product(id: "p6", title: "陶瓷手作马克杯 粗陶质感 300ml", price: 68, sold: "已售 3100", shop: "土与火", ratio: 0.85, tag: "手作"),
        Product(id: "p7", title: "羊毛混纺围巾 素色 男女同款", price: 139, sold: "已售 560", shop: "Novi 严选", ratio: 0.75, tag: "自营"),
        Product(id: "p8", title: "桌面收纳架 双层 实木", price: 98, sold: "已售 2400", shop: "木作日常", ratio: 0.95),
    ]
}
