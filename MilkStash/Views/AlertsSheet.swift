// AlertsSheet.swift
// Surfaced from the Home bell — a focused list of things that need attention.

import SwiftUI
import SwiftData

struct AlertsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<MilkBag> { $0.statusRaw == "In Stash" })
    private var stashBags: [MilkBag]
    @Query private var settings: [AppSettings]
    private var appSettings: AppSettings { settings.first ?? AppSettings() }

    private var unit: MilkUnit { appSettings.preferredUnit }
    private var totalOz: Double { stashBags.map(\.totalVolumeOz).reduce(0, +) }
    private var lowStash: Bool {
        totalOz > 0 && totalOz < appSettings.effectiveLowStashThresholdOz
    }
    private var expiring: [MilkBag] {
        StashService.expiringSoon(bags: stashBags, within: 7)
    }
    private var hasAlerts: Bool { lowStash || !expiring.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if !hasAlerts {
                        allClear
                    } else {
                        if lowStash { lowStashCard }
                        if !expiring.isEmpty { expiringSection }
                    }
                }
                .padding(.horizontal, Space.screenPad)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xl)
            }
            .background(Color.ffBg.ignoresSafeArea())
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.ffTerra)
                }
            }
        }
    }

    // MARK: - Sections

    private var allClear: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.ffSage)
            Text("All clear")
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(Color.ffInk)
            Text("Nothing needs your attention right now.")
                .font(.subheadline)
                .foregroundStyle(Color.ffInk2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var lowStashCard: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ffButter)
            Text("Stash is running low — \(UnitConversion.formatted(totalOz, in: unit)) remaining, below your \(UnitConversion.formatted(appSettings.effectiveLowStashThresholdOz, in: unit)) alert.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.ffInk2)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ffButterSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Radius.l).stroke(Color.ffButter.opacity(0.25), lineWidth: 0.5))
    }

    private var expiringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FFEyebrow(text: "EXPIRING WITHIN 7 DAYS")
            FFCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(expiring.enumerated()), id: \.element.id) { idx, bag in
                        FFExpiringRow(bag: bag, allBags: stashBags, preferredUnit: unit)
                        if idx < expiring.count - 1 {
                            FFDivider().padding(.leading, 16)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

#Preview {
    AlertsSheet()
        .modelContainer(PreviewData.container())
}
