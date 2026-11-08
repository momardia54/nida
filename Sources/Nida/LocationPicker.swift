import SwiftUI

/// "Use my location" + city search. Calls `onPick` with the chosen place.
struct LocationPicker: View {
    @ObservedObject var location: LocationService
    var onPick: (SavedLocation, _ isCurrent: Bool) -> Void

    @ViewState private var query = ""
    @ViewState private var results: [SavedLocation] = []
    @ViewState private var searching = false
    @ViewState private var searched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                location.requestCurrent { result in
                    if case .success(let loc) = result { onPick(loc, true) }
                }
            } label: {
                HStack {
                    if location.isLocating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "location.fill")
                    }
                    Text(location.isLocating ? "Locating…" : "Use my current location")
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(location.isLocating)

            if let error = location.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                TextField("Or search a city — e.g. Paris, Dakar, Toronto", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button("Search", action: search).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if searching {
                ProgressView().controlSize(.small)
            } else if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results) { r in
                        Button { onPick(r, false); results = []; query = "" } label: {
                            HStack {
                                Image(systemName: "mappin.circle.fill").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.title).font(.system(size: 12, weight: .medium))
                                    Text(r.timeZoneID.replacingOccurrences(of: "_", with: " "))
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 6).padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                        if r != results.last { Divider() }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            } else if searched {
                Text("No places found. Try a different spelling, or add the country.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func search() {
        searching = true
        location.search(query) { found in
            results = found
            searching = false
            searched = true
        }
    }
}
