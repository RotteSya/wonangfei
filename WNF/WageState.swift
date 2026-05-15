import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

final class WageState: ObservableObject {
    @Published var monthlySalary: Double = WageSettings.default.monthlySalary { didSet { persistSettings() } }
    @Published var workdaysPerMonth: Int = WageSettings.default.workdaysPerMonth { didSet { persistSettings() } }
    @Published var workStart: DateComponents = WageSettings.default.workStart.dateComponents { didSet { persistSettings() } }
    @Published var workEnd: DateComponents = WageSettings.default.workEnd.dateComponents { didSet { persistSettings() } }
    @Published var lunchStart: DateComponents = WageSettings.default.lunchStart.dateComponents { didSet { persistSettings() } }
    @Published var lunchEnd: DateComponents = WageSettings.default.lunchEnd.dateComponents { didSet { persistSettings() } }
    @Published var hasLunchBreak = WageSettings.default.hasLunchBreak { didSet { persistSettings() } }
    @Published var includeOvertime = WageSettings.default.includeOvertime { didSet { persistSettings() } }
    @Published var privacyMode = WageSettings.default.privacyMode { didSet { persistSettings() } }
    @Published var selectedWeekdays: Set<Int> = WageSettings.default.selectedWeekdays { didSet { persistSettings() } }
    @Published private(set) var currentDate = Date()

    private var clockTimer: Timer?
    private var endedWorkdayKey: String? {
        didSet { persistSettings() }
    }

    init() {
        apply(WNFSharedStore.loadSettings(from: WNFSharedStore.appDefaults, key: WNFSharedStore.appSettingsKey) ?? .default)
        persistSettings(reloadWidget: false)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    deinit {
        clockTimer?.invalidate()
    }

    var calculation: WageDay {
        WageCalculator.compute(settings: settings, now: currentDate)
    }

    var settings: WageSettings {
        WageSettings(
            monthlySalary: monthlySalary,
            workdaysPerMonth: workdaysPerMonth,
            workStart: WageTime(workStart),
            workEnd: WageTime(workEnd),
            lunchStart: WageTime(lunchStart),
            lunchEnd: WageTime(lunchEnd),
            hasLunchBreak: hasLunchBreak,
            includeOvertime: includeOvertime,
            overtimeMultiplier: WageSettings.default.overtimeMultiplier,
            privacyMode: privacyMode,
            selectedWeekdays: selectedWeekdays,
            endedWorkdayKey: endedWorkdayKey
        )
    }

    func endToday() {
        endedWorkdayKey = WageCalendar.dayKey(for: currentDate)
    }

    func bindingForTime(_ keyPath: ReferenceWritableKeyPath<WageState, DateComponents>) -> Date {
        DateComponents.calendar.date(from: self[keyPath: keyPath]) ?? .now
    }

    func updateTime(_ keyPath: ReferenceWritableKeyPath<WageState, DateComponents>, date: Date) {
        self[keyPath: keyPath] = DateComponents.calendar.dateComponents([.hour, .minute], from: date)
    }

    private func tick() {
        currentDate = Date()
        if let endedWorkdayKey, endedWorkdayKey != WageCalendar.dayKey(for: currentDate) {
            self.endedWorkdayKey = nil
        }
    }

    private func apply(_ settings: WageSettings) {
        monthlySalary = settings.monthlySalary
        workdaysPerMonth = settings.workdaysPerMonth
        workStart = settings.workStart.dateComponents
        workEnd = settings.workEnd.dateComponents
        lunchStart = settings.lunchStart.dateComponents
        lunchEnd = settings.lunchEnd.dateComponents
        hasLunchBreak = settings.hasLunchBreak
        includeOvertime = settings.includeOvertime
        privacyMode = settings.privacyMode
        selectedWeekdays = settings.selectedWeekdays
        endedWorkdayKey = settings.endedWorkdayKey
    }

    private func persistSettings(reloadWidget: Bool = true) {
        let current = settings
        WNFSharedStore.save(current, to: WNFSharedStore.appDefaults, key: WNFSharedStore.appSettingsKey)
        WNFSharedStore.save(current, to: WNFSharedStore.widgetDefaults, key: WNFSharedStore.widgetSettingsKey)

        #if canImport(WidgetKit)
        if reloadWidget {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }
}
