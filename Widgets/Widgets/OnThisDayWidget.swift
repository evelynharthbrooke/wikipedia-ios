import WidgetKit
import SwiftUI
import WMF

// MARK: - Widget

struct OnThisDayWidget: Widget {
    private let kind: String = WidgetController.SupportedWidget.onThisDay.identifier

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OnThisDayProvider(), content: { entry in
            OnThisDayView(entry: entry)
        })
        .configurationDisplayName(CommonStrings.onThisDayTitle)
        .description(WMFLocalizedString("widget-onthisday-description", value: "Explore what happened on this day in history.", comment: "Description for 'On this day' view in iOS widget gallery"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - TimelineProvider

struct OnThisDayProvider: TimelineProvider {

    // MARK: Nested Types

    public typealias Entry = OnThisDayEntry

    // MARK: Properties

    private let dataStore = OnThisDayData.shared

    // MARK: TimelineProvider

    func placeholder(in: Context) -> OnThisDayEntry {
        return dataStore.placeholderEntry
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OnThisDayEntry>) -> Void) {
        dataStore.fetchLatestAvailableOnThisDayEntry { entry in
            let currentDate = Date()
            let timeline = Timeline(entries: [entry], policy: .after(currentDate.dateAtMidnight() ?? currentDate))
            completion(timeline)
        }
    }

    func getSnapshot(in context: Context, completion: @escaping (OnThisDayEntry) -> Void) {
        dataStore.fetchLatestAvailableOnThisDayEntry(usingCache: context.isPreview) { entry in
            completion(entry)
        }
    }

}

/// A data source and operation helper for all On This Day of the day widget data
final class OnThisDayData {

    enum ErrorType {
        case noInternet, featureNotSupportedInLanguage

        var errorColor: Color {
            switch self {
            case .featureNotSupportedInLanguage:
                return Color(UIColor.base30)
            case .noInternet:
                return Color(white: 22/255)
            }
        }

        var errorText: String {
            /// These are intentionally in the iOS system language, not the app's primary language. Everything else in this widget is in the app's primary language.
            switch self {
            case .featureNotSupportedInLanguage:
                return WMFLocalizedString("on-this-day-language-does-not-support-error", value: "Your primary Wikipedia language does not support On this day. You can update your primary Wikipedia in the app’s Settings menu.", comment: "Error message shown when the user's primary language Wikipedia does not have the 'On this day' feature.")
            case .noInternet:
                return WMFLocalizedString("on-this-day-no-internet-error", value: "No data available", comment: "error message shown when device is not connected to internet")
            }
        }
    }

    // MARK: Properties

    static let shared = OnThisDayData()

    private var imageInfoFetcher = MWKImageInfoFetcher()

    private var dataStore: MWKDataStore {
        MWKDataStore.shared()
    }

	private var primaryAppLanguageSiteURL: URL? {
		return dataStore.languageLinkController.appLanguage?.siteURL()
	}

    // From https://en.wikipedia.org/api/rest_v1/feed/onthisday/events/01/15, taken on 03 Sept 2020.
    var placeholderEntry: OnThisDayEntry {
        let language = dataStore.languageLinkController.appLanguage
        let locale = NSLocale.wmf_locale(for: language?.languageCode)
        let isRTL = (MWLanguageInfo.semanticContentAttribute(forWMFLanguage: language?.languageCode) == UISemanticContentAttribute.forceRightToLeft)

        let fullDate: String
        let eventYear: String
        let monthDay: String
        let calendar = NSCalendar.wmf_utcGregorian()
        let date = calendar?.date(from: DateComponents(year: 2001, month: 01, day: 15, hour: 0, minute: 0, second: 0))
        if let date = date {
            let fullDateFormatter = DateFormatter.wmf_longDateGMTFormatter(for: language?.languageCode)
            fullDate = fullDateFormatter.string(from: date)
            let yearWithEraFormatter = DateFormatter.wmf_yearGMTDateFormatter(for: language?.languageCode)
            eventYear = yearWithEraFormatter.string(from: date)
            let monthDayFormatter = DateFormatter.wmf_monthNameDayNumberGMTFormatter(for: language?.languageCode)
            monthDay = monthDayFormatter.string(from: date)
        } else {
            fullDate = "January 15, 2001"
            eventYear = "2001"
            monthDay = "January 15"
        }

        let eventSnippet = WMFLocalizedString("widget-onthisday-placeholder-event-snippet", language: language?.languageCode, value: "Wikipedia, a free wiki content encyclopedia, goes online.", comment: "Placeholder text for On This Day widget: Event describing launch of Wikipedia")
        let articleSnippet = WMFLocalizedString("widget-onthisday-placeholder-article-snippet", language: language?.languageCode, value: "Free online encyclopedia that anyone can edit", comment: "Placeholder text for On This Day widget: Article description for an article about Wikipedia")

        // It seems that projects whose article is not titled "Wikipedia" (Arabic, for instance) all redirect this URL appropriately.
        let articleURL = URL(string: ((language?.siteURL().absoluteString ?? "https://en.wikipedia.org") + "/wiki/Wikipedia"))

        let entry: OnThisDayEntry = OnThisDayEntry(isRTLLanguage: isRTL,
                                          error: nil,

                                          onThisDayTitle: CommonStrings.onThisDayTitle(with: language?.languageCode),
                                          monthDay: monthDay,
                                          fullDate: fullDate,
                                          otherEventsText: CommonStrings.onThisDayFooterWith(with: 49, language: language?.languageCode),
                                          contentURL: URL(string: "https://en.wikipedia.org/wiki/Wikipedia:On_this_day/Today"),
                                          eventSnippet: eventSnippet,
                                          eventYear: eventYear,
                                          eventYearsAgo: String(format: WMFLocalizedDateFormatStrings.yearsAgo(forWikiLanguage: language?.languageCode), locale: locale, (Calendar.current.component(.year, from: Date()) - 2001)),
                                          articleTitle: CommonStrings.plainWikipediaName(with: language?.languageCode),
                                          articleSnippet: articleSnippet,
                                          articleImage: UIImage(named: "W"),
                                          articleURL: articleURL,
                                          yearRange: CommonStrings.onThisDayHeaderDateRangeMessage(with: language?.languageCode, locale: locale, lastEvent: "69", firstEvent: "2019"))
        return entry
    }

    // MARK: Public
    
    func fetchLatestAvailableOnThisDayEntry(usingCache: Bool = false, _ completion: @escaping (OnThisDayEntry) -> Void) {
        guard let appLanguage = MWKDataStore.shared().languageLinkController.appLanguage, WMFOnThisDayEventsFetcher.isOnThisDaySupported(by: appLanguage.languageCode) else {
            let errorEntry = OnThisDayEntry.errorEntry(for: .featureNotSupportedInLanguage)
            completion(errorEntry)
            return
        }

        let moc = dataStore.viewContext
        moc.perform {
			guard let latest = moc.newestGroup(of: .onThisDay, forSiteURL: self.primaryAppLanguageSiteURL),
                  latest.isForToday
            else {
                guard !usingCache else {
                    completion(self.placeholderEntry)
                    return
                }
                self.fetchLatestOnThisDayEntryFromNetwork(completion)
                return
            }
            self.assembleOnThisDayFromContentGroup(latest, usingImageCache: usingCache, completion: completion)
        }
    }

    // MARK: Private

    private func fetchLatestOnThisDayEntryFromNetwork(_ completion: @escaping (OnThisDayEntry) -> Void) {
        dataStore.feedContentController.updateFeedSourcesUserInitiated(false) {
            let moc = self.dataStore.viewContext
            moc.perform {
				guard let latest = moc.newestGroup(of: .onThisDay, forSiteURL: self.primaryAppLanguageSiteURL) else {
                    // If there's no content even after a network fetch, it's likely an error
                    self.handleNoInternetError(completion)
                    return
                }
                self.assembleOnThisDayFromContentGroup(latest, completion: completion)
            }
        }
    }
    
    private func assembleOnThisDayFromContentGroup(_ contentGroup: WMFContentGroup, usingImageCache: Bool = false, completion: @escaping (OnThisDayEntry) -> Void) {
        guard let previewEvents = contentGroup.contentPreview as? [WMFFeedOnThisDayEvent],
              let previewEvent = previewEvents.first
        else {
            completion(placeholderEntry)
            return
        }

        let sendDataToWidget: (UIImage?) -> Void = { image in
            DispatchQueue.main.async {
                guard let entry = OnThisDayEntry(contentGroup: contentGroup, image: image) else {
                    completion(self.placeholderEntry)
                    return
                }
                completion(entry)
            }
        }

        let imageURLRaw = previewEvent.articlePreviews?.first?.thumbnailURL
        guard let imageURL = imageURLRaw, !usingImageCache else {
            /// The argument sent to `sendDataToWidget` on the next line could be nil because `imageURLRaw` is nil, or `cachedImage` returns nil.
            /// `sendDataToWidget` will appropriately handle a nil image, so we don't need to worry about that here.
            sendDataToWidget(ImageCacheController.shared?.cachedImage(withURL: imageURLRaw)?.staticImage)
            return
        }

        ImageCacheController.shared?.fetchImage(withURL: imageURL, failure: { _ in
            sendDataToWidget(nil)
        }, success: { fetchedImage in
            sendDataToWidget(fetchedImage.image.staticImage)
        })
    }
    
    private func handleNoInternetError(_ completion: @escaping (OnThisDayEntry) -> Void) {
        let errorEntry = OnThisDayEntry.errorEntry(for: .noInternet)
        completion(errorEntry)
    }
}

// MARK: - Model

struct OnThisDayEntry: TimelineEntry {
    let date = Date()
    let isRTLLanguage: Bool
    let error: OnThisDayData.ErrorType?

    let onThisDayTitle: String
    let monthDay: String
    let fullDate: String
    let otherEventsText: String
    let contentURL: URL?
    let eventSnippet: String?
    let eventYear: String
    let eventYearsAgo: String?
    let articleTitle: String?
    let articleSnippet: String?
    let articleImage: UIImage?
    let articleURL: URL?
    let yearRange: String
}

extension OnThisDayEntry {
    init?(contentGroup: WMFContentGroup, image: UIImage?) {
        guard
            let midnightUTCDate = contentGroup.midnightUTCDate,
            let calendar = NSCalendar.wmf_utcGregorian(),
            let previewEvents = contentGroup.contentPreview as? [WMFFeedOnThisDayEvent],
            let previewEvent = previewEvents.first,
            let allEvents = contentGroup.fullContent?.object as? [WMFFeedOnThisDayEvent],
            let earliestEventYear = allEvents.last?.yearString,
            let latestEventYear = allEvents.first?.yearString,
            let article = previewEvents.first?.articlePreviews?.first,
            let year = previewEvent.year?.intValue,
            let eventsCount = contentGroup.countOfFullContent?.intValue
        else {
            return nil
        }
        let language = contentGroup.siteURL?.wmf_language
        let monthDayFormatter = DateFormatter.wmf_monthNameDayNumberGMTFormatter(for: language)
        monthDay = monthDayFormatter.string(from: midnightUTCDate)
        var components = calendar.components([.month, .year, .day], from: midnightUTCDate)
        components.year = year
        if let date = calendar.date(from: components) {
            let fullDateFormatter = DateFormatter.wmf_longDateGMTFormatter(for: language)
            fullDate = fullDateFormatter.string(from: date)
            let yearWithEraFormatter = DateFormatter.wmf_yearGMTDateFormatter(for: language)
            eventYear = yearWithEraFormatter.string(from: date)
        } else {
            fullDate = ""
            eventYear = ""
        }
        onThisDayTitle = CommonStrings.onThisDayTitle(with: language)
        isRTLLanguage = contentGroup.isRTL
        error = nil
        otherEventsText = CommonStrings.onThisDayFooterWith(with: (eventsCount - 1), language: language)
        eventSnippet = previewEvent.text
        articleTitle = article.displayTitle
        articleSnippet = article.descriptionOrSnippet
        articleImage = image
        articleURL = article.articleURL
        let locale = NSLocale.wmf_locale(for: language)
        let currentYear = Calendar.current.component(.year, from: Date())
        let yearsSinceEvent = currentYear - year
        eventYearsAgo = String(format: WMFLocalizedDateFormatStrings.yearsAgo(forWikiLanguage: language), locale: locale, yearsSinceEvent)
        yearRange = CommonStrings.onThisDayHeaderDateRangeMessage(with: language, locale: locale, lastEvent: earliestEventYear, firstEvent: latestEventYear)

        if let previewEventIndex = allEvents.firstIndex(of: previewEvent),
           let dynamicURL = URL(string: "https://en.wikipedia.org/wiki/Wikipedia:On_this_day/Today?\(previewEventIndex)") {
            contentURL = dynamicURL
        } else {
            contentURL = URL(string: "https://en.wikipedia.org/wiki/Wikipedia:On_this_day/Today")
        }
    }

    static func errorEntry(for error: OnThisDayData.ErrorType) -> OnThisDayEntry {
        let isRTL = Locale.lineDirection(forLanguage: Locale.autoupdatingCurrent.languageCode ?? "en") == .rightToLeft
        let destinationURL = URL(string: "wikipedia://explore")
        return OnThisDayEntry(isRTLLanguage: isRTL, error: error, onThisDayTitle: "", monthDay: "", fullDate: "", otherEventsText: "", contentURL: destinationURL, eventSnippet: nil, eventYear: "", eventYearsAgo: nil, articleTitle: nil, articleSnippet: nil, articleImage: nil, articleURL: nil, yearRange: "")
    }
}
