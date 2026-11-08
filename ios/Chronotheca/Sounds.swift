import UIKit

/// Толчки в руку (P263, P267): у каждого движения свой.
enum Feel {
    // Отклики — заранее заведённые, одни на всё приложение (P829). Прежде
    // каждый толчок заводил отклик заново, без подготовки: iPhone будил
    // вибромотор в миг толчка, экран на кадр-два замирал — «дёргается в
    // момент виброотклика» (P800, видео автора к 251).
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let lightOne = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notice = UINotificationFeedbackGenerator()

    /// Разбудить отклики заранее — палец только лёг на ленту (P829).
    static func warm() {
        soft.prepare()
        lightOne.prepare()
    }

    /// Экран тронулся — опускается или поднимается.
    static func thud() {
        soft.impactOccurred(intensity: 0.8)
        soft.prepare()
    }
    /// Лёгкое касание: шаг назад, точка легла в текст.
    static func light() {
        lightOne.impactOccurred()
        lightOne.prepare()
    }
    /// Щелчок колёсика и готового ответа.
    static func tick() {
        selection.selectionChanged()
        selection.prepare()
    }
    /// Дело сделано.
    static func done() {
        notice.notificationOccurred(.success)
    }
    /// Дело или точка поднялись под пальцем долгим нажатием (P362).
    static func lift() {
        rigid.impactOccurred()
    }
    /// Бумажный листок лёг на место.
    static func paper() {
        soft.impactOccurred(intensity: 0.9)
    }
}
