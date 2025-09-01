// ===============================
// File: Glyphs.swift
// ===============================
import SwiftUI

func glyph(for piece: Piece) -> String {
    switch (piece.type, piece.color) {
    case (.pawn, .white): return "♙"
    case (.knight, .white): return "♘"
    case (.bishop, .white): return "♗"
    case (.rook, .white): return "♖"
    case (.queen, .white): return "♕"
    case (.king, .white): return "♔"
    case (.pawn, .black): return "♟"
    case (.knight, .black): return "♞"
    case (.bishop, .black): return "♝"
    case (.rook, .black): return "♜"
    case (.queen, .black): return "♛"
    case (.king, .black): return "♚"
    }
}
