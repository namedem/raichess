// ===============================
// File: Puzzles.swift
// ===============================
import SwiftUI

// MARK: - Модель задач

struct ChessPuzzle: Identifiable {
    let id = UUID()
    let title: String
    let fen: String          // <placement> <side> ... (остальное можно не указывать)
    let mateIn: Int

    var sideToMove: PieceColor {
        let parts = fen.split(separator: " ")
        if parts.count >= 2, parts[1] == "w" { return .white }
        return .black
    }
}

// База «мат в 1» (для старта)
let SampleMateIn1: [ChessPuzzle] = [
    ChessPuzzle(
        title: "Мат в 1 (#1)",
        fen: "4k3/8/8/8/8/8/4Q3/4K3 w - - 0 1",
        mateIn: 1
    ),
    ChessPuzzle(
        title: "Мат в 1 (#2)",
        fen: "6k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1",
        mateIn: 1
    ),
    ChessPuzzle(
        title: "Мат в 1 (#3)",
        fen: "4k3/8/8/8/8/5Q2/8/4K3 w - - 0 1",
        mateIn: 1
    ),
]

// MARK: - FEN → Board (минимально, без рокировок/эн-пассана)

extension Board {
    static func fromFEN(_ fen: String) -> Board {
        let tokens = fen.split(separator: " ")
        guard let placement = tokens.first else { return .starting() }

        var squares: [Piece?] = Array(repeating: nil, count: 64)
        let ranks = placement.split(separator: "/")
        guard ranks.count == 8 else { return .starting() }

        for (rIndex, rankStr) in ranks.enumerated() {
            var file = 0
            for ch in rankStr {
                if let n = ch.wholeNumberValue {
                    file += n
                } else {
                    guard file < 8 else { continue }
                    let color: PieceColor = ch.isUppercase ? .white : .black
                    let t: PieceType
                    switch ch.lowercased() {
                    case "k": t = .king
                    case "q": t = .queen
                    case "r": t = .rook
                    case "b": t = .bishop
                    case "n": t = .knight
                    case "p": t = .pawn
                    default:  t = .pawn
                    }
                    // FEN даёт ранги сверху вниз; у нас rank=0 снизу
                    let boardRank = 7 - rIndex
                    let idx = boardRank * 8 + file
                    if 0..<64 ~= idx {
                        squares[idx] = Piece(type: t, color: color)
                    }
                    file += 1
                }
            }
        }
        var b = Board.starting()
        b.squares = squares
        return b
    }
}

// MARK: - Список задач (упрощённый для компилятора)

struct PuzzleListView: View {
    let puzzles: [ChessPuzzle] = SampleMateIn1

    var body: some View {
        List {
            Section("Мат в 1") {
                ForEach(puzzles) { p in
                    NavigationLink(
                        destination: PuzzlePlayView(puzzle: p)
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.title)
                                .font(.headline)

                            HStack(spacing: 6) {
                                Text("Ход:")
                                Text(p.sideToMove == .white ? "Белые" : "Чёрные")
                                Text("• FEN")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Шахматные задачи")
    }
}

// MARK: - Экран решения задачи

struct PuzzlePlayView: View {
    let puzzle: ChessPuzzle
    @StateObject private var game = ChessGame()
    @State private var showResult: (success: Bool, text: String)? = nil

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(puzzle.title).font(.headline)
                    Text("Цель: мат в \(puzzle.mateIn). Ходят \(puzzle.sideToMove == .white ? "белые" : "чёрные").")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Сброс") { loadPosition() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            ZStack {
                ChessBoardView(game: game, style: .classic)
                    .padding(.horizontal)

                if let res = showResult {
                    Text(res.text)
                        .font(.title3).bold()
                        .padding(12)
                        .background(res.success ? .green.opacity(0.85) : .red.opacity(0.85))
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Задача")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadPosition() }
        .onChange(of: game.sideToMove) { checkIfSolved() }
    }

    private func loadPosition() {
        game.vsAI = false
        game.result = nil
        game.selected = nil
        game.legalTargets = []
        game.board = Board.fromFEN(puzzle.fen)
        game.sideToMove = puzzle.sideToMove
        showResult = nil
    }

    // Проверка решения «мат в 1»: после твоего хода у соперника нет ходов и он под шахом
    private func checkIfSolved() {
        guard puzzle.mateIn == 1 else { return }
        let justMoved = puzzle.sideToMove
        // если сейчас очередь соперника — значит, ты сделал ход
        if game.sideToMove != justMoved {
            let moves = game.listAllLegalMoves(for: game.sideToMove, on: game.board)
            let inCheck = game.inCheck(on: game.board, color: game.sideToMove)
            if moves.isEmpty && inCheck {
                showResult = (true, "Верно! Мат.")
            } else {
                showResult = (false, "Не мат. Попробуй ещё.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    showResult = nil
                }
            }
        }
    }
}
