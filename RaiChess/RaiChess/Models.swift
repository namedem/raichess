// ===============================
// File: Models.swift
// ===============================
import Foundation

enum PieceColor: String { case white, black }

enum PieceType: String {
    case pawn, knight, bishop, rook, queen, king
}

struct Piece: Equatable {
    let type: PieceType
    let color: PieceColor
}

struct Square: Hashable, Equatable {
    let file: Int  // 0..7 for a..h
    let rank: Int  // 0..7 for 1..8 (0 = rank 1)
    var index: Int { rank * 8 + file }
    var name: String { "\(Character(UnicodeScalar(97 + file)!))\(rank + 1)" }

    static func from(index: Int) -> Square { Square(file: index % 8, rank: index / 8) }
}

struct Move: Equatable {
    let from: Square
    let to: Square
    let captured: Piece?
    let promotion: PieceType?
}

struct Board {
    var squares: [Piece?] = Array(repeating: nil, count: 64)

    static func starting() -> Board {
        var b = Board()
        func place(_ type: PieceType, _ color: PieceColor, _ file: Int, _ rank: Int) {
            b.squares[rank * 8 + file] = Piece(type: type, color: color)
        }
        let back: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for f in 0..<8 {
            place(back[f], .white, f, 0)
            place(.pawn, .white, f, 1)
            place(.pawn, .black, f, 6)
            place(back[f], .black, f, 7)
        }
        return b
    }

    func piece(at square: Square) -> Piece? { squares[square.index] }

    mutating func move(from: Square, to: Square) {
        squares[to.index] = squares[from.index]
        squares[from.index] = nil
    }

    mutating func apply(_ m: Move) {
        squares[m.to.index] = squares[m.from.index]
        squares[m.from.index] = nil
        if let promo = m.promotion, let p = squares[m.to.index] {
            squares[m.to.index] = Piece(type: promo, color: p.color)
        }
    }

    mutating func undo(_ m: Move) {
        let moved = squares[m.to.index]
        squares[m.from.index] = moved
        squares[m.to.index] = m.captured
    }

    func findKing(of color: PieceColor) -> Square? {
        for i in 0..<64 {
            if let p = squares[i], p.type == .king, p.color == color {
                return Square.from(index: i)
            }
        }
        return nil
    }
}
