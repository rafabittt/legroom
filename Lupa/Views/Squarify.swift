import CoreGraphics

/// "Squarified" treemap (Bruls, Huizing and van Wijk): splits a rectangle into
/// areas proportional to the values, keeping the pieces as square as possible.
enum Squarify {
    /// `values` must be in descending order and contain no zeros.
    static func layout(values: [Double], in bounds: CGRect) -> [CGRect] {
        guard !values.isEmpty, bounds.width > 0, bounds.height > 0 else { return values.map { _ in .zero } }
        let total = values.reduce(0, +)
        guard total > 0 else { return values.map { _ in .zero } }
        let scale = Double(bounds.width * bounds.height) / total
        var rects: [CGRect] = []
        rects.reserveCapacity(values.count)
        var remaining = bounds
        var row: [Double] = []
        var i = 0
        while i < values.count {
            let v = values[i] * scale
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worst(row, side) >= worst(row + [v], side) {
                row.append(v); i += 1
            } else {
                rects += place(row, in: &remaining)
                row.removeAll(keepingCapacity: true)
            }
        }
        if !row.isEmpty { rects += place(row, in: &remaining) }
        return rects
    }

    private static func worst(_ row: [Double], _ w: Double) -> Double {
        let s = row.reduce(0, +)
        guard let mx = row.max(), let mn = row.min(), s > 0, w > 0, mn > 0 else { return .infinity }
        let w2 = w * w, s2 = s * s
        return max(w2 * mx / s2, s2 / (w2 * mn))
    }

    private static func place(_ row: [Double], in remaining: inout CGRect) -> [CGRect] {
        let s = row.reduce(0, +)
        var out: [CGRect] = []
        if remaining.width >= remaining.height {
            let w = remaining.height > 0 ? CGFloat(s) / remaining.height : 0
            var y = remaining.minY
            for v in row {
                let h = w > 0 ? CGFloat(v) / w : 0
                out.append(CGRect(x: remaining.minX, y: y, width: w, height: h))
                y += h
            }
            remaining = CGRect(x: remaining.minX + w, y: remaining.minY, width: max(0, remaining.width - w), height: remaining.height)
        } else {
            let h = remaining.width > 0 ? CGFloat(s) / remaining.width : 0
            var x = remaining.minX
            for v in row {
                let w = h > 0 ? CGFloat(v) / h : 0
                out.append(CGRect(x: x, y: remaining.minY, width: w, height: h))
                x += w
            }
            remaining = CGRect(x: remaining.minX, y: remaining.minY + h, width: remaining.width, height: max(0, remaining.height - h))
        }
        return out
    }
}
