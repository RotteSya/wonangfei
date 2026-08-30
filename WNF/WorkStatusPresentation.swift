struct WorkStatusPresentation: Equatable {
    var label: String
    var quotes: [String]
    var mascotAssetName: String

    init(status: WorkStatus) {
        label = status.label
        switch status {
        case .off:
            quotes = [
                "我今天不坐工位。",
                "休息日，我先把工牌收好。",
                "今天这张椅子归空气。",
                "我去过自己的时间了。"
            ]
            mascotAssetName = "CowFrontSad"
        case .before:
            quotes = [
                "我还没坐稳，钱也没开机。",
                "工位在等，我再慢一点。",
                "咖啡到了，工时还没到。",
                "先把今天的不情愿放桌上。"
            ]
            mascotAssetName = "CowFrontSad"
        case .morning:
            quotes = [
                "我坐稳了，钱开始一点点涨。",
                "这封邮件，我先看第三遍。",
                "上午的精神，先借给咖啡。",
                "PPT 翻一页，工时走一点。"
            ]
            mascotAssetName = "CowThreeQ"
        case .lunch:
            quotes = [
                "我先吃饭，工位替我空着。",
                "午休这会儿，钱也歇口气。",
                "我趴一会儿，下午再见。",
                "饭吃完了，电还没充满。"
            ]
            mascotAssetName = "CowFrontSad"
        case .afternoon:
            quotes = [
                "我先眯会儿，钱还在涨。",
                "下午的会，我坐旁边听着。",
                "我把第三杯咖啡续上了。",
                "工时慢慢走，我也慢慢撑。"
            ]
            mascotAssetName = "CowFrontSad"
        case .done:
            quotes = [
                "我收工了，今天的钱也到站。",
                "电脑合上，工位明天再见。",
                "今天这班，我陪你坐完了。",
                "工牌先摘，回家再说。"
            ]
            mascotAssetName = "CowThreeQ"
        }
    }
}
