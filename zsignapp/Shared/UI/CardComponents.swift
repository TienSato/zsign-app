//
//  CardComponents.swift
//  zsignapp
//


import SwiftUI

// MARK: - Khung màn hình

struct CardScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Metric.cardSpacing) {
                content
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas.ignoresSafeArea())
    }
}

// MARK: - Nhóm thẻ

struct CardGroup<Content: View>: View {
    var title: String? = nil
    var footnote: String? = nil
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 4)
            }

            VStack(spacing: 0) {
                content
            }
            .cardStyle(padding: 0)

            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct CardDivider: View {
    var inset: CGFloat = Theme.Metric.cardPadding + Theme.Metric.iconBox + 12

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

// MARK: - Hàng

struct CardRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconTint: Color? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            iconBox
            labels
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, Theme.Metric.cardPadding)
        .padding(.vertical, 12)
        .frame(minHeight: Theme.Metric.rowHeight)
        .contentShape(Rectangle())
    }

    private var iconBox: some View {
        Image(systemName: icon)
            .font(.system(size: Theme.Metric.iconSize, weight: .semibold))
            .foregroundStyle(iconTint ?? Color.accentColor)
            .frame(width: Theme.Metric.iconBox, alignment: .center)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension CardRow where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, iconTint: Color? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconTint = iconTint
        self.trailing = EmptyView()
    }
}

struct CardChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.ink3)
    }
}

struct CardNavRow<Destination: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconTint: Color? = nil
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            CardRow(icon: icon, title: title, subtitle: subtitle, iconTint: iconTint) {
                CardChevron()
            }
        }
        .buttonStyle(.plain)
    }
}

struct CardToggleRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconTint: Color? = nil
    @Binding var isOn: Bool

    var body: some View {
        CardRow(icon: icon, title: title, subtitle: subtitle, iconTint: iconTint) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

struct CardValueRow: View {
    let icon: String
    let title: String
    let value: String
    var iconTint: Color? = nil

    var body: some View {
        CardRow(icon: icon, title: title, iconTint: iconTint) {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
        }
    }
}

// MARK: - Nút

struct FilledButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint ?? (role == .destructive ? Color.red : Color.accentColor))
            )
        }
        .buttonStyle(.plain)
    }
}
