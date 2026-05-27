struct WorkStatusPresentation: Equatable {
    var label: String
    var quotes: [String]
    var mascotAssetName: String

    init(status: WorkStatus) {
        switch status {
        case .before:
            label = "尚未开工"
            quotes = [
                "别急，钱还没开始挣。",
                "起床气和工位都还没暖。",
                "通勤路上时薪是零。",
                "今天先攒一点不情愿。",
                "钱包没动，心率先动。",
                "开机前的最后一口自由。"
            ]
            mascotAssetName = "CowFrontSad"
        case .morning:
            label = "上午搬砖中"
            quotes = [
                "早上的两小时最值钱。",
                "工位坐稳，钱开始一点点掉。",
                "上午的专注度都给了奶茶。",
                "搬砖搬到第三个 PPT 了。",
                "邮件已读，心却没读。",
                "在会议里假装思考的样子。"
            ]
            mascotAssetName = "CowThreeQ"
        case .lunch:
            label = "午休回血"
            quotes = [
                "吃饭的时候不发工资。",
                "二十块的饭，半小时的命。",
                "回血中，请勿打扰工位。",
                "午休是上半场的伤停补时。",
                "嚼的是饭，想的是下班。",
                "趴着小睡，假装是在思考。"
            ]
            mascotAssetName = "CowFrontSad"
        case .afternoon:
            label = "下午挺挺"
            quotes = [
                "再忍忍，钱在涨。",
                "下午三点的会，是命运的一种。",
                "再撑两小时就有外卖自由。",
                "咖啡续到第三杯，钱还差一截。",
                "丧但还顶得住，时薪还在跑。",
                "今天的窝囊费已经过半。"
            ]
            mascotAssetName = "CowFrontSad"
        case .done:
            label = "今日通关"
            quotes = [
                "今天又把房租挣回来了。",
                "下班的脚步比早上轻了。",
                "工位收摊，钱已落袋。",
                "今天的搬砖到此为止。",
                "通关结算，奖励是回家。",
                "明天再继续，今天先逃。"
            ]
            mascotAssetName = "CowThreeQ"
        }
    }
}
