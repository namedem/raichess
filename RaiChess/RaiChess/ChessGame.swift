// ===============================
// File: ChessGame.swift
// ===============================
import Foundation
import Combine
import Dispatch

final class ChessGame: ObservableObject {

    // MARK: - Публичное состояние
    @Published var board: Board = .starting()
    @Published var sideToMove: PieceColor = .white
    @Published var selected: Square? = nil
    @Published var legalTargets: Set<Square> = []

    enum GameResult { case checkmate(winner: PieceColor), stalemate }
    @Published var result: GameResult? = nil

    // Промоция: если не nil — ждём выбор фигуры пользователем
    @Published var pendingPromotion: (from: Square, to: Square, color: PieceColor)? = nil

    // MARK: - Рокировка (флаги)
    private var whiteKingMoved = false
    private var whiteRookAMoved = false   // a1
    private var whiteRookHMoved = false   // h1
    private var blackKingMoved = false
    private var blackRookAMoved = false   // a8
    private var blackRookHMoved = false   // h8

    // MARK: - Настройки ИИ
    enum AISkill: String, CaseIterable { case beginner, casual, club, expert, master, grandmaster, enginePlus }
    struct SearchConfig { let maxDepth: Int; let timeLimit: Double; let quiescence: Bool }

    @Published var vsAI: Bool = true
    @Published var aiColor: PieceColor = .black
    @Published var aiSkill: AISkill = .casual

    private func config(for skill: AISkill) -> SearchConfig {
        switch skill {
        case .beginner:     return .init(maxDepth: 1, timeLimit: 0.2, quiescence: false)
        case .casual:       return .init(maxDepth: 2, timeLimit: 0.4, quiescence: false)
        case .club:         return .init(maxDepth: 3, timeLimit: 0.7, quiescence: true)
        case .expert:       return .init(maxDepth: 4, timeLimit: 1.2, quiescence: true)
        case .master:       return .init(maxDepth: 5, timeLimit: 2.5, quiescence: true)
        case .grandmaster:  return .init(maxDepth: 6, timeLimit: 5.0, quiescence: true)
        case .enginePlus:   return .init(maxDepth: 7, timeLimit: 10.0, quiescence: true)
        }
    }

    // MARK: - Публичные действия
    func reset() {
        board = .starting()
        sideToMove = .white
        selected = nil
        legalTargets = []
        result = nil
        pendingPromotion = nil

        // сброс флагов рокировки
        whiteKingMoved = false; whiteRookAMoved = false; whiteRookHMoved = false
        blackKingMoved = false; blackRookAMoved = false; blackRookHMoved = false

        // если ИИ белыми — сразу ход
        maybeAIMove()
    }

    func select(_ square: Square) {
        guard result == nil else { return }
        if let sel = selected {
            if sel == square {
                selected = nil
                legalTargets = []
                return
            }
            if legalTargets.contains(square) {
                makeMove(from: sel, to: square)
                return
            }
        }
        if let p = board.piece(at: square), p.color == sideToMove {
            selected = square
            legalTargets = legalMoves(from: square)
        } else {
            selected = nil
            legalTargets = []
        }
    }

    // ===== ХОД ИГРОКА / ДВИЖОКОВЫЙ ХОД =====
    func makeMove(from: Square, to: Square) {
        guard result == nil else { return }

        let movedPiece = board.piece(at: from)

        // --- ЧЕЛОВЕК: если пешка идёт на последнюю горизонталь — спросим фигуру
        if let p = movedPiece, p.type == .pawn, pendingPromotion == nil {
            if (p.color == .white && to.rank == 7) || (p.color == .black && to.rank == 0) {
                pendingPromotion = (from: from, to: to, color: p.color)
                selected = nil
                legalTargets = []
                return
            }
        }

        let move = Move(from: from, to: to, captured: board.piece(at: to), promotion: nil)

        // --- Рокировка: король двигается на 2 клетки по горизонтали — двигаем соответствующую ладью
        if let king = movedPiece, king.type == .king, abs(to.file - from.file) == 2 {
            if king.color == .white {
                if to.file == 6 {
                    // e1->g1, h1->f1
                    board.apply(Move(from: Square(file: 7, rank: 0), to: Square(file: 5, rank: 0), captured: nil, promotion: nil))
                } else if to.file == 2 {
                    // e1->c1, a1->d1
                    board.apply(Move(from: Square(file: 0, rank: 0), to: Square(file: 3, rank: 0), captured: nil, promotion: nil))
                }
            } else {
                if to.file == 6 {
                    // e8->g8, h8->f8
                    board.apply(Move(from: Square(file: 7, rank: 7), to: Square(file: 5, rank: 7), captured: nil, promotion: nil))
                } else if to.file == 2 {
                    // e8->c8, a8->d8
                    board.apply(Move(from: Square(file: 0, rank: 7), to: Square(file: 3, rank: 7), captured: nil, promotion: nil))
                }
            }
        }

        // основной ход
        board.apply(move)

        // --- обновление флагов рокировки
        if let p = movedPiece {
            switch (p.type, p.color, from.file, from.rank) {
            case (.king, .white, 4, 0): whiteKingMoved = true
            case (.king, .black, 4, 7): blackKingMoved = true
            case (.rook, .white, 0, 0): whiteRookAMoved = true
            case (.rook, .white, 7, 0): whiteRookHMoved = true
            case (.rook, .black, 0, 7): blackRookAMoved = true
            case (.rook, .black, 7, 7): blackRookHMoved = true
            default: break
            }
        }
        if let cap = move.captured {
            switch (cap.type, cap.color, to.file, to.rank) {
            case (.rook, .white, 0, 0): whiteRookAMoved = true
            case (.rook, .white, 7, 0): whiteRookHMoved = true
            case (.rook, .black, 0, 7): blackRookAMoved = true
            case (.rook, .black, 7, 7): blackRookHMoved = true
            default: break
            }
        }

        selected = nil
        legalTargets = []
        sideToMove = (sideToMove == .white) ? .black : .white
        checkGameEnd()
        maybeAIMove()
    }

    // подтверждение выбора фигуры в промоции
    func confirmPromotion(_ type: PieceType) {
        guard let pp = pendingPromotion else { return }
        // применяем именно ход с промоцией
        let move = Move(from: pp.from, to: pp.to, captured: board.piece(at: pp.to), promotion: type)
        board.apply(move)

        pendingPromotion = nil
        sideToMove = (sideToMove == .white) ? .black : .white
        checkGameEnd()
        maybeAIMove()
    }

    // MARK: - Ходы (генерация)
    func pseudoLegalMoves(from: Square) -> [Move] {
        guard let piece = board.piece(at: from) else { return [] }
        var out: [Move] = []

        func push(_ f: Int, _ r: Int) {
            guard (0..<8).contains(f), (0..<8).contains(r) else { return }
            let to = Square(file: f, rank: r)
            let cap = board.piece(at: to)
            if let occ = cap {
                if occ.color != piece.color { out.append(Move(from: from, to: to, captured: cap, promotion: nil)) }
            } else {
                out.append(Move(from: from, to: to, captured: nil, promotion: nil))
            }
        }

        switch piece.type {
        case .knight:
            let deltas = [(1,2),(2,1),(-1,2),(-2,1),(1,-2),(2,-1),(-1,-2),(-2,-1)]
            for (df, dr) in deltas { push(from.file + df, from.rank + dr) }

        case .bishop:
            out += ray(from, (1,1)) + ray(from, (-1,1)) + ray(from, (1,-1)) + ray(from, (-1,-1))

        case .rook:
            out += ray(from, (1,0)) + ray(from, (-1,0)) + ray(from, (0,1)) + ray(from, (0,-1))

        case .queen:
            out += ray(from, (1,0)) + ray(from, (-1,0)) + ray(from, (0,1)) + ray(from, (0,-1))
            out += ray(from, (1,1)) + ray(from, (-1,1)) + ray(from, (1,-1)) + ray(from, (-1,-1))

        case .king:
            // обычные шаги
            for df in -1...1 {
                for dr in -1...1 where (df != 0 || dr != 0) {
                    push(from.file + df, from.rank + dr)
                }
            }

            // ======== РОКИРОВКА ========
            if piece.color == .white,
               from.file == 4, from.rank == 0,
               !whiteKingMoved,
               !inCheck(on: board, color: .white) {

                // короткая e1->g1
                if board.piece(at: Square(file: 5, rank: 0)) == nil,
                   board.piece(at: Square(file: 6, rank: 0)) == nil,
                   !isSquareAttacked(Square(file: 5, rank: 0), by: .black, on: board),
                   !isSquareAttacked(Square(file: 6, rank: 0), by: .black, on: board),
                   !whiteRookHMoved, board.piece(at: Square(file: 7, rank: 0))?.type == .rook {
                    out.append(Move(from: from, to: Square(file: 6, rank: 0), captured: nil, promotion: nil))
                }

                // длинная e1->c1
                if board.piece(at: Square(file: 3, rank: 0)) == nil,
                   board.piece(at: Square(file: 2, rank: 0)) == nil,
                   board.piece(at: Square(file: 1, rank: 0)) == nil,
                   !isSquareAttacked(Square(file: 3, rank: 0), by: .black, on: board),
                   !isSquareAttacked(Square(file: 2, rank: 0), by: .black, on: board),
                   !whiteRookAMoved, board.piece(at: Square(file: 0, rank: 0))?.type == .rook {
                    out.append(Move(from: from, to: Square(file: 2, rank: 0), captured: nil, promotion: nil))
                }
            }

            if piece.color == .black,
               from.file == 4, from.rank == 7,
               !blackKingMoved,
               !inCheck(on: board, color: .black) {

                // короткая e8->g8
                if board.piece(at: Square(file: 5, rank: 7)) == nil,
                   board.piece(at: Square(file: 6, rank: 7)) == nil,
                   !isSquareAttacked(Square(file: 5, rank: 7), by: .white, on: board),
                   !isSquareAttacked(Square(file: 6, rank: 7), by: .white, on: board),
                   !blackRookHMoved, board.piece(at: Square(file: 7, rank: 7))?.type == .rook {
                    out.append(Move(from: from, to: Square(file: 6, rank: 7), captured: nil, promotion: nil))
                }

                // длинная e8->c8
                if board.piece(at: Square(file: 3, rank: 7)) == nil,
                   board.piece(at: Square(file: 2, rank: 7)) == nil,
                   board.piece(at: Square(file: 1, rank: 7)) == nil,
                   !isSquareAttacked(Square(file: 3, rank: 7), by: .white, on: board),
                   !isSquareAttacked(Square(file: 2, rank: 7), by: .white, on: board),
                   !blackRookAMoved, board.piece(at: Square(file: 0, rank: 7))?.type == .rook {
                    out.append(Move(from: from, to: Square(file: 2, rank: 7), captured: nil, promotion: nil))
                }
            }
            // ===========================

        case .pawn:
            let dir = (piece.color == .white) ? 1 : -1
            let f1 = from.rank + dir
            if (0..<8).contains(f1) {
                let one = Square(file: from.file, rank: f1)
                if board.piece(at: one) == nil {
                    out.append(Move(from: from, to: one, captured: nil,
                                    promotion: pawnPromo(to: one, color: piece.color)))
                    let startRank = (piece.color == .white) ? 1 : 6
                    if from.rank == startRank {
                        let f2 = from.rank + 2 * dir
                        let two = Square(file: from.file, rank: f2)
                        if board.piece(at: two) == nil {
                            out.append(Move(from: from, to: two, captured: nil, promotion: nil))
                        }
                    }
                }
            }
            for df in [-1, 1] {
                let nf = from.file + df
                let nr = from.rank + dir
                if (0..<8).contains(nf), (0..<8).contains(nr) {
                    let capSq = Square(file: nf, rank: nr)
                    if let cap = board.piece(at: capSq), cap.color != piece.color {
                        out.append(Move(from: from, to: capSq, captured: cap,
                                        promotion: pawnPromo(to: capSq, color: piece.color)))
                    }
                }
            }
        }
        return out
    }

    private func pawnPromo(to: Square, color: PieceColor) -> PieceType? {
        // для ИИ — автопромоция в ферзя
        if color == .white && to.rank == 7 { return .queen }
        if color == .black && to.rank == 0 { return .queen }
        return nil
    }

    private func ray(_ from: Square, _ d: (Int, Int)) -> [Move] {
        var out: [Move] = []
        var f = from.file + d.0
        var r = from.rank + d.1
        guard let me = board.piece(at: from) else { return out }
        while (0..<8).contains(f) && (0..<8).contains(r) {
            let to = Square(file: f, rank: r)
            if let occ = board.piece(at: to) {
                if occ.color != me.color { out.append(Move(from: from, to: to, captured: occ, promotion: nil)) }
                break
            } else {
                out.append(Move(from: from, to: to, captured: nil, promotion: nil))
            }
            f += d.0
            r += d.1
        }
        return out
    }

    func legalMoves(from: Square) -> Set<Square> {
        guard let p = board.piece(at: from), p.color == sideToMove else { return [] }
        var result: Set<Square> = []
        for m in pseudoLegalMoves(from: from) {
            var b = board; b.apply(m)
            if !inCheck(on: b, color: p.color) { result.insert(m.to) }
        }
        return result
    }

    func listAllLegalMoves(for color: PieceColor, on b: Board) -> [Move] {
        var moves: [Move] = []
        for i in 0..<64 {
            let from = Square.from(index: i)
            if let p = b.squares[i], p.color == color {
                let pseudo = pseudoLegalMovesStatic(from: from, on: b)
                for m in pseudo {
                    var bb = b; bb.apply(m)
                    if !inCheck(on: bb, color: color) { moves.append(m) }
                }
            }
        }
        return moves
    }

    private func pseudoLegalMovesStatic(from: Square, on b: Board) -> [Move] {
        // упрощённая версия для дерева поиска (без рокировки)
        guard let piece = b.piece(at: from) else { return [] }
        var out: [Move] = []

        func push(_ f: Int, _ r: Int) {
            guard (0..<8).contains(f), (0..<8).contains(r) else { return }
            let to = Square(file: f, rank: r)
            let cap = b.piece(at: to)
            if let occ = cap {
                if occ.color != piece.color { out.append(Move(from: from, to: to, captured: occ, promotion: nil)) }
            } else {
                out.append(Move(from: from, to: to, captured: nil, promotion: nil))
            }
        }
        func ray(_ d:(Int,Int)) {
            var f = from.file + d.0, r = from.rank + d.1
            while (0..<8).contains(f) && (0..<8).contains(r) {
                let to = Square(file: f, rank: r)
                if let occ = b.piece(at: to) {
                    if occ.color != piece.color { out.append(Move(from: from, to: to, captured: occ, promotion: nil)) }
                    break
                } else {
                    out.append(Move(from: from, to: to, captured: nil, promotion: nil))
                }
                f += d.0; r += d.1
            }
        }

        switch piece.type {
        case .knight: [(1,2),(2,1),(-1,2),(-2,1),(1,-2),(2,-1),(-1,-2),(-2,-1)].forEach{ push(from.file+$0.0, from.rank+$0.1) }
        case .bishop: [(1,1),(-1,1),(1,-1),(-1,-1)].forEach{ ray($0) }
        case .rook:   [(1,0),(-1,0),(0,1),(0,-1)].forEach{ ray($0) }
        case .queen:  [(1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,1),(1,-1),(-1,-1)].forEach{ ray($0) }
        case .king:
            for df in -1...1 { for dr in -1...1 where (df != 0 || dr != 0) { push(from.file+df, from.rank+dr) } }
        case .pawn:
            let dir = (piece.color == .white) ? 1 : -1
            let f1 = from.rank + dir
            if (0..<8).contains(f1) {
                let one = Square(file: from.file, rank: f1)
                if b.piece(at: one) == nil {
                    out.append(Move(from: from, to: one, captured: nil, promotion: pawnPromoStatic(to: one, color: piece.color)))
                    let startRank = (piece.color == .white) ? 1 : 6
                    if from.rank == startRank {
                        let f2 = from.rank + 2*dir
                        let two = Square(file: from.file, rank: f2)
                        if b.piece(at: two) == nil { out.append(Move(from: from, to: two, captured: nil, promotion: nil)) }
                    }
                }
            }
            for df in [-1,1] {
                let nf = from.file + df, nr = from.rank + dir
                if (0..<8).contains(nf),(0..<8).contains(nr) {
                    let capSq = Square(file: nf, rank: nr)
                    if let cap = b.piece(at: capSq), cap.color != piece.color {
                        out.append(Move(from: from, to: capSq, captured: cap, promotion: pawnPromoStatic(to: capSq, color: piece.color)))
                    }
                }
            }
        }
        return out
    }

    private func pawnPromoStatic(to: Square, color: PieceColor) -> PieceType? {
        if color == .white && to.rank == 7 { return .queen }
        if color == .black && to.rank == 0 { return .queen }
        return nil
    }

    // MARK: - Шахи/атаки
    func inCheck(on b: Board, color: PieceColor) -> Bool {
        guard let k = b.findKing(of: color) else { return false }
        return isSquareAttacked(k, by: (color == .white ? .black : .white), on: b)
    }

    func isSquareAttacked(_ sq: Square, by attacker: PieceColor, on b: Board) -> Bool {
        // кони
        for (df,dr) in [(1,2),(2,1),(-1,2),(-2,1),(1,-2),(2,-1),(-1,-2),(-2,-1)] {
            let f = sq.file + df, r = sq.rank + dr
            if (0..<8).contains(f),(0..<8).contains(r),
               let p = b.piece(at: Square(file:f, rank:r)), p.color == attacker, p.type == .knight { return true }
        }
        // пешки
        let dir = (attacker == .white) ? 1 : -1
        for df in [-1,1] {
            let f = sq.file + df, r = sq.rank - dir
            if (0..<8).contains(f),(0..<8).contains(r),
               let p = b.piece(at: Square(file:f, rank:r)), p.color == attacker, p.type == .pawn { return true }
        }
        // король рядом
        for df in -1...1 { for dr in -1...1 where (df != 0 || dr != 0) {
            let f = sq.file + df, r = sq.rank + dr
            if (0..<8).contains(f),(0..<8).contains(r),
               let p = b.piece(at: Square(file:f, rank:r)), p.color == attacker, p.type == .king { return true }
        }}
        // лучевые фигуры
        func ray(_ d:(Int,Int)) -> Bool {
            var f = sq.file + d.0, r = sq.rank + d.1
            while (0..<8).contains(f) && (0..<8).contains(r) {
                let s = Square(file:f, rank:r)
                if let p = b.piece(at: s) {
                    if p.color == attacker {
                        if (d.0 == 0 || d.1 == 0) && (p.type == .rook || p.type == .queen) { return true }
                        if (d.0 != 0 && d.1 != 0) && (p.type == .bishop || p.type == .queen) { return true }
                    }
                    return false
                }
                f += d.0; r += d.1
            }
            return false
        }
        return ray((1,0)) || ray((-1,0)) || ray((0,1)) || ray((0,-1))
            || ray((1,1)) || ray((-1,1)) || ray((1,-1)) || ray((-1,-1))
    }

    // MARK: - ИИ (minimax + alpha-beta + квиесценс)
    func bestMove(for color: PieceColor, depth: Int) -> Move? {
        let moves = listAllLegalMoves(for: color, on: board)
        guard !moves.isEmpty else { return nil }
        var best: Move? = nil
        var bestScore = color == .white ? -1e9 : 1e9
        let maximizing = (color == .white)
        var alpha = -1e9, beta = 1e9
        for m in moves {
            var b = board; b.apply(m)
            var a = alpha, be = beta
            let s = minimax(board: b, depth: depth - 1, maximizing: !maximizing,
                            toMove: (color == .white ? .black : .white), alpha: &a, beta: &be)
            if maximizing { if s > bestScore { bestScore = s; best = m; alpha = max(alpha, s) } }
            else { if s < bestScore { bestScore = s; best = m; beta = min(beta, s) } }
        }
        return best
    }

    func bestMoveTimed(for color: PieceColor, maxDepth: Int, timeLimit: Double, useQuiescence: Bool) -> Move? {
        let deadline = Date().addingTimeInterval(timeLimit)
        var lastBest: Move? = nil
        self.useQuiescence = useQuiescence
        for d in 1...maxDepth {
            if Date() >= deadline { break }
            if let m = bestMove(for: color, depth: d) { lastBest = m }
            if Date() >= deadline { break }
        }
        return lastBest
    }

    private var useQuiescence: Bool = true

    private func minimax(board b: Board, depth: Int, maximizing: Bool, toMove: PieceColor, alpha: inout Double, beta: inout Double) -> Double {
        if depth == 0 {
            return useQuiescence
                ? quiescence(board: b, alpha: &alpha, beta: &beta, toMove: toMove, maximizing: maximizing)
                : evaluate(b)
        }
        let moves = listAllLegalMoves(for: toMove, on: b)
        if moves.isEmpty {
            if inCheck(on: b, color: toMove) { return maximizing ? -1e6 : 1e6 } // мат
            return 0 // пат
        }
        var bb = b
        if maximizing {
            var value = -1e9
            for m in moves {
                bb = b; bb.apply(m)
                var a = alpha, be = beta
                let score = minimax(board: bb, depth: depth - 1, maximizing: false,
                                    toMove: (toMove == .white ? .black : .white), alpha: &a, beta: &be)
                value = max(value, score); alpha = max(alpha, value); if alpha >= beta { break }
            }
            return value
        } else {
            var value = 1e9
            for m in moves {
                bb = b; bb.apply(m)
                var a = alpha, be = beta
                let score = minimax(board: bb, depth: depth - 1, maximizing: true,
                                    toMove: (toMove == .white ? .black : .white), alpha: &a, beta: &be)
                value = min(value, score); beta = min(beta, value); if alpha >= beta { break }
            }
            return value
        }
    }

    private func quiescence(board b: Board, alpha: inout Double, beta: inout Double, toMove: PieceColor, maximizing: Bool) -> Double {
        let standPat = evaluate(b)
        if maximizing {
            if standPat >= beta { return beta }
            alpha = max(alpha, standPat)
        } else {
            if standPat <= alpha { return alpha }
            beta = min(beta, standPat)
        }
        let moves = captureMoves(for: toMove, on: b)
        var bb = b
        if maximizing {
            var value = -1e9
            for m in moves {
                bb = b; bb.apply(m)
                var a = alpha, be = beta
                let score = quiescence(board: bb, alpha: &a, beta: &be,
                                       toMove: (toMove == .white ? .black : .white), maximizing: false)
                value = max(value, score); alpha = max(alpha, value); if alpha >= beta { break }
            }
            return value
        } else {
            var value = 1e9
            for m in moves {
                bb = b; bb.apply(m)
                var a = alpha, be = beta
                let score = quiescence(board: bb, alpha: &a, beta: &be,
                                       toMove: (toMove == .white ? .black : .white), maximizing: true)
                value = min(value, score); beta = min(beta, value); if alpha >= beta { break }
            }
            return value
        }
    }

    private func captureMoves(for color: PieceColor, on b: Board) -> [Move] {
        var res: [Move] = []
        for i in 0..<64 {
            let from = Square.from(index: i)
            if let p = b.squares[i], p.color == color {
                for m in pseudoLegalMovesStatic(from: from, on: b) where m.captured != nil {
                    var bb = b; bb.apply(m)
                    if !inCheck(on: bb, color: color) { res.append(m) }
                }
            }
        }
        return res
    }

    private func evaluate(_ b: Board) -> Double {
        var score = 0.0
        for i in 0..<64 {
            if let p = b.squares[i] {
                let sq = Square.from(index: i)
                score += (p.color == .white ? 1 : -1) * (material(p) + pstBonus(for: p, at: sq))
            }
        }
        return score
    }

    private func material(_ p: Piece) -> Double {
        switch p.type {
        case .pawn: return 1
        case .knight, .bishop: return 3.2
        case .rook: return 5.1
        case .queen: return 9.5
        case .king: return 0
        }
    }

    private func pstBonus(for piece: Piece, at sq: Square) -> Double {
        let (f, r) = (sq.file, sq.rank)
        let rf = piece.color == .white ? r : 7 - r
        switch piece.type {
        case .pawn:   return [0,0.05,0.10,0.20,0.30,0.20,0.10,0][rf]
        case .knight: let d = abs(3.5 - Double(f)) + abs(3.5 - Double(r)); return 0.4 - 0.1*d
        case .bishop: return 0.05 * Double(min(f,7-f) + min(r,7-r))
        case .rook:   return (rf >= 5 ? 0.15 : 0)
        case .queen:  return 0.02 * Double(min(f,7-f) + min(r,7-r))
        case .king:   return (rf <= 1 ? 0.3 : -0.2)
        }
    }

    // MARK: - Завершение партии
    func checkGameEnd() {
        let moves = listAllLegalMoves(for: sideToMove, on: board)
        if moves.isEmpty {
            if inCheck(on: board, color: sideToMove) { result = .checkmate(winner: sideToMove == .white ? .black : .white) }
            else { result = .stalemate }
        }
    }

    // MARK: - ИИ-триггер
    func maybeAIMove() {
        guard result == nil, vsAI, sideToMove == aiColor else { return }
        let cfg = config(for: aiSkill)
        let color = aiColor
        DispatchQueue.global(qos: .userInitiated).async {
            let best = self.bestMoveTimed(for: color, maxDepth: cfg.maxDepth, timeLimit: cfg.timeLimit, useQuiescence: cfg.quiescence)
            if let best {
                DispatchQueue.main.async {
                    self.board.apply(best)
                    self.sideToMove = (self.sideToMove == .white) ? .black : .white
                    self.checkGameEnd()
                    self.maybeAIMove()
                }
            }
        }
    }
}
