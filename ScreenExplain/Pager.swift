import Foundation

/// Разбиение ответа на страницы по измеренным высотам блоков.
nonisolated enum Pager {
    /// Смещения начала страниц по высотам блоков (сверху вниз, между блоками `spacing`).
    ///
    /// Естественные начала страниц — жадно: блок добавляется к странице, пока суммарная высота ≤ pageHeight;
    /// не влезающий блок начинает новую страницу. Если до следующего начала больше pageHeight (высокий блок),
    /// вставляются промежуточные страницы шагом `max(pageHeight − lineHeight, pageHeight / 2)` — с перекрытием
    /// в строку, чтобы строка на стыке не терялась.
    ///
    /// Затем: ни одно смещение не больше `end = max(0, total − pageHeight)` (дальше ScrollView не прокрутит),
    /// последняя страница — ровно `end`, дублей нет. Соседние страницы ближе pageHeight / 3 не оставляются:
    /// естественное начало рядом с предыдущей страницей пропускается (остаётся первая из пары), рядом с `end` —
    /// тоже (остаётся `end`). Инвариант покрытия: соседние смещения отличаются не больше чем на pageHeight,
    /// поэтому листание не пропускает текст; если ради него шаг у конца вышел бы короче pageHeight / 3,
    /// промежуток до `end` делится пополам. Единственная тесная пара, которая может остаться, — [0, end] при end < pageHeight / 3.
    ///
    /// Пустой вход, pageHeight ≤ 0 или всё влезает → [0].
    static func pageOffsets(heights: [CGFloat], spacing: CGFloat, pageHeight: CGFloat, lineHeight: CGFloat) -> [CGFloat] {
        guard pageHeight > 0, !heights.isEmpty else { return [0] }
        let total = heights.reduce(0, +) + spacing * CGFloat(heights.count - 1)
        let end = max(0, total - pageHeight)
        guard end > 0 else { return [0] }

        // Естественные начала страниц (кроме 0).
        var starts: [CGFloat] = []
        var y: CGFloat = 0
        var used: CGFloat = 0
        for h in heights {
            if used > 0 && used + spacing + h > pageHeight {
                starts.append(y)
                used = h
            } else {
                used += used == 0 ? h : spacing + h
            }
            y += h + spacing
        }

        let step = max(pageHeight - max(lineHeight, 0), pageHeight / 2)
        let minGap = pageHeight / 3
        var result: [CGFloat] = [0]

        for target in starts.map({ min($0, end) }) + [end] {
            // Дотягиваемся до target шагами, чтобы между страницами не было больше pageHeight.
            while target - result[result.count - 1] > pageHeight {
                let last = result[result.count - 1]
                var next = last + step
                if end - next < minGap {
                    // Шаг упёрся бы в конец: делим остаток до end пополам (обе части в [pageHeight/2, 2/3·pageHeight]).
                    next = (last + end) / 2
                }
                result.append(next)
            }
            let last = result[result.count - 1]
            if target < end && target - last >= minGap && end - target >= minGap {
                result.append(target)
            }
        }
        result.append(end)
        return result
    }

    /// Индекс страницы для текущего смещения прокрутки: последняя страница, чей offset ≤ contentOffset + 1.
    static func pageIndex(forOffset contentOffset: CGFloat, pageOffsets: [CGFloat]) -> Int {
        pageOffsets.lastIndex { $0 <= contentOffset + 1 } ?? 0
    }
}
