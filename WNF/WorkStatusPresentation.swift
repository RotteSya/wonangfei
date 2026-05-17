struct WorkStatusPresentation: Equatable {
    var label: String
    var quote: String
    var mascotAssetName: String

    init(status: WorkStatus) {
        switch status {
        case .before:
            label = "尚未开工"
            quote = "别急，钱还没开始挣。"
            mascotAssetName = "CowFrontSad"
        case .morning:
            label = "上午搬砖中"
            quote = "早上的两小时最值钱。"
            mascotAssetName = "CowThreeQ"
        case .lunch:
            label = "午休回血"
            quote = "吃饭的时候不发工资。"
            mascotAssetName = "CowFrontSad"
        case .afternoon:
            label = "下午挺挺"
            quote = "再忍忍，钱在涨。"
            mascotAssetName = "CowFrontSad"
        case .done:
            label = "今日通关"
            quote = "今天又把房租挣回来了。"
            mascotAssetName = "CowThreeQ"
        }
    }
}
