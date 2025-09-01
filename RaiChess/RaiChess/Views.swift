// ===============================
// File: Views.swift
// ===============================
import SwiftUI

// MARK: - Хранилище настроек/выбора
enum BoardStyle: String, CaseIterable, Identifiable {
    case classic, blue, green, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: return "Classic"
        case .blue:    return "Blue"
        case .green:   return "Green"
        case .dark:    return "Dark"
        }
    }
}
struct BoardTheme { let light: Color; let dark: Color }
func theme(for style: BoardStyle) -> BoardTheme {
    switch style {
    case .classic:
        return .init(light: Color(red:0.95, green:0.90, blue:0.75),
                     dark:  Color(red:0.75, green:0.55, blue:0.35))
    case .blue:
        return .init(light: Color(red:0.88, green:0.93, blue:0.98),
                     dark:  Color(red:0.36, green:0.55, blue:0.80))
    case .green:
        return .init(light: Color(red:0.90, green:0.97, blue:0.90),
                     dark:  Color(red:0.42, green:0.63, blue:0.42))
    case .dark:
        return .init(light: Color(red:0.30, green:0.30, blue:0.33),
                     dark:  Color(red:0.17, green:0.17, blue:0.20))
    }
}

// MARK: - Точка входа
struct GameViewRoot: View {
    var body: some View { NavigationStack { MenuScreen() } }
}

// MARK: - Главное меню
struct MenuScreen: View {
    @AppStorage("defaultBoardStyle") private var defaultStyle: BoardStyle = .classic
    @State private var showNewGame = false
    @State private var showPuzzles  = false
    @State private var showHistory  = false
    @State private var showSettings = false
    @AppStorage("hasSavedGame") private var hasSavedGame: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Text("RaiChess").font(.largeTitle.bold()).padding(.top, 12)

            VStack(spacing: 14) {
                MenuCard(icon: "play.circle.fill",
                         title: hasSavedGame ? "Продолжить" : "Новая игра",
                         subtitle: hasSavedGame ? "Вернуться к последней партии" : "Выберите сложность и стиль") {
                    showNewGame = true
                }
                MenuCard(icon: "puzzlepiece.extension.fill",
                         title: "Шахматные задачи",
                         subtitle: "Тактика и тренировка") {
                    showPuzzles = true
                }
                MenuCard(icon: "clock.fill",
                         title: "История партий",
                         subtitle: "Сохранённые результаты (скоро)") {
                    showHistory = true
                }
                MenuCard(icon: "gearshape.fill",
                         title: "Настройки",
                         subtitle: "Тема, звук, вибро") {
                    showSettings = true
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .background(LinearGradient(colors: [Color(.systemBackground),
                                            Color(.secondarySystemBackground)],
                                   startPoint: .top, endPoint: .bottom))
        .navigationDestination(isPresented: $showNewGame) { NewGameScreen() }
        .navigationDestination(isPresented: $showPuzzles)  { PuzzlesScreen() }
        .navigationDestination(isPresented: $showHistory)  { HistoryScreen() }
        .navigationDestination(isPresented: $showSettings) { SettingsScreen(defaultStyle: $defaultStyle) }
    }
}

struct MenuCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .foregroundStyle(.tint)
                        .font(.system(size: 22, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Мастер новой игры
struct NewGameScreen: View {
    @State private var vsAI: Bool = true
    @State private var aiColor: PieceColor = .black
    @State private var skill: ChessGame.AISkill = .casual
    @State private var style: BoardStyle
    @State private var start = false

    init() {
        if let raw = UserDefaults.standard.string(forKey: "defaultBoardStyle"),
           let saved = BoardStyle(rawValue: raw) {
            _style = State(initialValue: saved)
        } else {
            _style = State(initialValue: .classic)
        }
    }

    var body: some View {
        Form {
            Section(header: Text("Режим")) {
                Toggle("Играть против ИИ", isOn: $vsAI)
                Picker("Цвет ИИ", selection: $aiColor) {
                    Text("Белые").tag(PieceColor.white)
                    Text("Чёрные").tag(PieceColor.black)
                }
                .pickerStyle(.segmented)
            }

            Section(header: Text("Сложность ИИ")) {
                Picker("Уровень", selection: $skill) {
                    Text("Beginner").tag(ChessGame.AISkill.beginner)
                    Text("Casual").tag(ChessGame.AISkill.casual)
                    Text("Club").tag(ChessGame.AISkill.club)
                    Text("Expert").tag(ChessGame.AISkill.expert)
                    Text("Master").tag(ChessGame.AISkill.master)
                    Text("Grandmaster").tag(ChessGame.AISkill.grandmaster)
                    Text("Engine+").tag(ChessGame.AISkill.enginePlus)
                }
            }

            Section(header: Text("Стиль доски")) {
                Picker("Тема", selection: $style) {
                    ForEach(BoardStyle.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button {
                    start = true
                } label: {
                    Label("Старт", systemImage: "play.fill").font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Новая игра")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $start) {
            GameView(style: style, vsAI: vsAI, aiColor: aiColor, aiSkill: skill)
                .onAppear { UserDefaults.standard.set(true, forKey: "hasSavedGame") }
        }
        .onDisappear {
            UserDefaults.standard.set(style.rawValue, forKey: "defaultBoardStyle")
        }
    }
}

// MARK: - Плейсхолдеры/навигация
struct PuzzlesScreen: View {
    var body: some View {
        PuzzleListView()   // экран из Puzzles.swift
    }
}
struct HistoryScreen: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("История партий").font(.title.bold())
            Text("Пока пусто. Сохраним партии после завершения игры.")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
struct SettingsScreen: View {
    @Binding var defaultStyle: BoardStyle
    @State private var soundOn = true
    @State private var hapticsOn = true
    @State private var flipForBlack = true

    var body: some View {
        Form {
            Section(header: Text("Внешний вид")) {
                Picker("Тема доски по умолчанию", selection: $defaultStyle) {
                    ForEach(BoardStyle.allCases) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.segmented)
            }
            Section(header: Text("Общие")) {
                Toggle("Звук", isOn: $soundOn)
                Toggle("Вибро", isOn: $hapticsOn)
                Toggle("Переворачивать доску за чёрных", isOn: $flipForBlack)
            }
        }
        .navigationTitle("Настройки")
    }
}

// MARK: - Экран игры
struct GameView: View {
    @StateObject var game = ChessGame()
    let style: BoardStyle
    let vsAI: Bool
    let aiColor: PieceColor
    let aiSkill: ChessGame.AISkill

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Ход: " + (game.sideToMove == .white ? "Белые" : "Чёрные"))
                    .font(.headline)
                Spacer()
                Toggle("ИИ", isOn: $game.vsAI).labelsHidden()
                Picker("", selection: $game.aiColor) {
                    Text("Белые").tag(PieceColor.white)
                    Text("Чёрные").tag(PieceColor.black)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)

                Menu("Сложность: \(label(for: game.aiSkill))") {
                    ForEach(ChessGame.AISkill.allCases, id: \.self) { s in
                        Button {
                            game.aiSkill = s
                            game.maybeAIMove()
                        } label: {
                            if game.aiSkill == s { Label(label(for: s), systemImage: "checkmark") }
                            else { Text(label(for: s)) }
                        }
                    }
                }
                Button("Новая") { game.reset() }.buttonStyle(.bordered)
            }
            .padding(.horizontal)

            ZStack {
                ChessBoardView(game: game, style: style).padding(.horizontal)
                if let res = game.result { ResultBanner(result: res) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Игра")
        .navigationBarTitleDisplayMode(.inline)
        .dynamicTypeSize(.medium)
        .onAppear {
            game.vsAI = vsAI
            game.aiColor = aiColor
            game.aiSkill = aiSkill
            game.reset()
        }
        .onDisappear { UserDefaults.standard.set(false, forKey: "hasSavedGame") }
        .onChange(of: game.aiColor) { game.reset() }
        .onChange(of: game.vsAI)    { game.reset() }
        .onChange(of: game.aiSkill) { game.maybeAIMove() }
    }

    private func label(for s: ChessGame.AISkill) -> String {
        switch s {
        case .beginner: return "Beginner"
        case .casual: return "Casual"
        case .club: return "Club"
        case .expert: return "Expert"
        case .master: return "Master"
        case .grandmaster: return "Grandmaster"
        case .enginePlus: return "Engine+"
        }
    }
}

// MARK: - Доска (единый gesture)
struct ChessBoardView: View {
    @ObservedObject var game: ChessGame
    let style: BoardStyle

    var body: some View {
        let colors = theme(for: style)
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cell = size / 8.0
            ZStack(alignment: .topLeading) {
                ForEach(0..<64, id: \.self) { idx in
                    let sq = Square.from(index: idx)
                    Rectangle()
                        .fill(((sq.file + sq.rank) % 2 == 0) ? colors.light : colors.dark)
                        .frame(width: cell, height: cell)
                        .position(x: CGFloat(sq.file) * cell + cell/2,
                                  y: CGFloat(7 - sq.rank) * cell + cell/2)
                        .cornerRadius(4)
                }
                ForEach(Array(game.legalTargets), id: \.self) { sq in
                    Circle()
                        .fill(Color.black.opacity(0.18))
                        .frame(width: cell * 0.28, height: cell * 0.28)
                        .position(x: CGFloat(sq.file) * cell + cell/2,
                                  y: CGFloat(7 - sq.rank) * cell + cell/2)
                        .allowsHitTesting(false)
                }
                ForEach(0..<64, id: \.self) { idx in
                    let sq = Square.from(index: idx)
                    if let piece = game.board.piece(at: sq) {
                        Glyph(type: piece.type, color: piece.color)
                            .font(.system(size: cell * 0.7))
                            .frame(width: cell, height: cell)
                            .position(x: CGFloat(sq.file) * cell + cell/2,
                                      y: CGFloat(7 - sq.rank) * cell + cell/2)
                            .allowsHitTesting(false)
                    }
                }
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: size, height: size)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                var f = Int(value.location.x / cell)
                                var rt = Int(value.location.y / cell)
                                f = max(0, min(7, f))
                                rt = max(0, min(7, rt))
                                let r = 7 - rt
                                game.select(Square(file: f, rank: r))
                            }
                    )
            }
            .frame(width: size, height: size)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(radius: 8, y: 6)
        }
        .aspectRatio(1, contentMode: .fit)
        .dynamicTypeSize(.medium)
    }
}

// MARK: - Глифы/баннер
struct Glyph: View {
    let type: PieceType
    let color: PieceColor
    var body: some View {
        Text(symbol)
            .foregroundColor(color == .white ? .white : .black)
            .shadow(radius: 1)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .accessibilityHidden(true)
    }
    private var symbol: String {
        switch (type, color) {
        case (.king,   .white): return "♔"
        case (.queen,  .white): return "♕"
        case (.rook,   .white): return "♖"
        case (.bishop, .white): return "♗"
        case (.knight, .white): return "♘"
        case (.pawn,   .white): return "♙"
        case (.king,   .black): return "♚"
        case (.queen,  .black): return "♛"
        case (.rook,   .black): return "♜"
        case (.bishop, .black): return "♝"
        case (.knight, .black): return "♞"
        case (.pawn,   .black): return "♟"
        }
    }
}
struct ResultBanner: View {
    let result: ChessGame.GameResult
    var body: some View {
        Group {
            switch result {
            case .checkmate(let winner):
                Text("Мат. Победили \(winner == .white ? "Белые" : "Чёрные").")
            case .stalemate:
                Text("Пат. Ничья.")
            }
        }
        .font(.title3).padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}
