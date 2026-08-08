import SwiftUI

struct DateEditor: View {
    @Binding var content: DateContent
    var focus: BlockFocusChain? = nil

    /// What the month FIELD shows (the model keeps the numeric month): digits
    /// while typing, snapped to the ALL-CAPS abbreviation ("AUG") on blur —
    /// the digit-only-format-on-blur convention, display-side.
    @State private var monthDisplay: String

    init(content: Binding<DateContent>, focus: BlockFocusChain? = nil) {
        self._content = content
        self.focus = focus
        let month = content.wrappedValue.date.map {
            Calendar(identifier: .gregorian).component(.month, from: $0)
        }
        self._monthDisplay = State(initialValue: MonthFormat.abbreviation(for: month) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SelectAllTextField(placeholder: "Label (e.g. Date: — leave blank for none)",
                                text: $content.label,
                                focusKey: focus.key(FocusFields.dateLabel),
                                focusBinding: focus.binding,
                                onTab: focus.tab(FocusFields.dateLabel))
                .frame(height: standardFieldHeight)

            HStack {
                Text("Date")
                // No keyboardType overrides anywhere in the app: every field
                // uses the default text keyboard so the hardware-keyboard
                // assistant strip (keyboard + mic icons) is identical on all
                // of them — see Editor conventions. (The old SwiftUI
                // .keyboardType(.numberPad) modifiers here were no-ops on the
                // bridged fields anyway.)
                SelectAllTextField(placeholder: "DD", text: dayText,
                                   focusKey: focus.key(FocusFields.dateDay),
                                   focusBinding: focus.binding,
                                   onTab: focus.tab(FocusFields.dateDay))
                    .frame(width: 52, height: standardFieldHeight)
                SelectAllTextField(placeholder: "MM", text: monthText,
                                   focusKey: focus.key(FocusFields.dateMonth),
                                   focusBinding: focus.binding,
                                   onTab: focus.tab(FocusFields.dateMonth),
                                   onEndEditing: snapMonthDisplay)
                    .frame(width: 52, height: standardFieldHeight)
                SelectAllTextField(placeholder: "YYYY", text: yearText,
                                   focusKey: focus.key(FocusFields.dateYear),
                                   focusBinding: focus.binding,
                                   onTab: focus.tab(FocusFields.dateYear))
                    .frame(width: 80, height: standardFieldHeight)
                // One tap to stamp the current date — mainly for reopened
                // report PDFs, which come back with the ORIGINAL date (the
                // exact-copy import decision). Shown only while the stored
                // date ISN'T already today (empty counts as not-today), so
                // its very presence flags a stale date; stamping it makes
                // the button disappear.
                if !isToday {
                    Button("Today") {
                        setToday()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var isToday: Bool {
        guard let date = content.date else { return false }
        return cal.isDateInToday(date)
    }

    private func setToday() {
        var c = cal.dateComponents([.day, .month, .year], from: Date())
        c.hour = 12; c.minute = 0; c.second = 0   // noon: avoid tz midnight edge
        if let date = cal.date(from: c) {
            content.date = date
        }
        monthDisplay = MonthFormat.abbreviation(for: c.month) ?? ""
    }

    private var cal: Calendar { Calendar(identifier: .gregorian) }

    private func comps() -> DateComponents {
        if let d = content.date {
            return cal.dateComponents([.day, .month, .year], from: d)
        }
        return DateComponents()
    }

    // Rebuild content.date from day/month/year; nil when all three empty.
    private func setDate(day: Int?? = nil, month: Int?? = nil, year: Int?? = nil) {
        var c = comps()
        if let day   { c.day = day }
        if let month { c.month = month }
        if let year  { c.year = year }
        if c.day == nil && c.month == nil && c.year == nil {
            content.date = nil; return
        }
        c.hour = 12; c.minute = 0; c.second = 0   // noon: avoid tz midnight edge
        if let newDate = cal.date(from: c) {
            content.date = newDate
        }
    }

    private var dayText: Binding<String> {
        Binding(
            get: { comps().day.map(String.init) ?? "" },
            set: { setDate(day: .some(Int($0))) }
        )
    }

    private var monthText: Binding<String> {
        Binding(
            get: { monthDisplay },
            set: { v in
                monthDisplay = v
                setDate(month: .some(MonthFormat.parse(v)))
            }
        )
    }

    /// Blur: show "AUG" when a valid month is stored; unparseable text stays
    /// visible as typed (the whole DOB-style guard — never reformat garbage).
    private func snapMonthDisplay() {
        if let abbrev = MonthFormat.abbreviation(for: comps().month) {
            monthDisplay = abbrev
        }
    }

    private var yearText: Binding<String> {
        Binding(
            get: { comps().year.map(String.init) ?? "" },
            set: { setDate(year: .some(Int($0))) }
        )
    }
}

#Preview {
    struct Demo: View {
        @State private var content = DateContent(
            label: "Date of exam:",
            date: Calendar(identifier: .gregorian)
                .date(from: DateComponents(year: 2026, month: 6, day: 7, hour: 12))
        )
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                DateEditor(content: $content)
                Text("Stored: \(content.label) \(content.date.map(String.init(describing:)) ?? "nil")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    return Demo()
}
