import Foundation

/// The tree as a vault's records, and back. The memory vault names a bud by its id.
extension Bud {
    /// Where the bud is in the memory vault.
    public var path: String { id.uuidString }

    /// The bud for a path: the path's own id when it is one, else an id derived from the path, so
    /// the same path is the same bud on every load.
    public static func id(forPath path: String) -> UUID {
        if let id = UUID(uuidString: path) { return id }
        var high: UInt64 = 0xcbf2_9ce4_8422_2325
        var low: UInt64 = 0x8422_2325_cbf2_9ce4
        for byte in path.utf8 {
            high = (high ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            low = (low &* 0x0000_0100_0000_01b3) ^ UInt64(byte) &+ high
        }
        var bytes: [UInt8] = []
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: high >> UInt64(shift))) }
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: low >> UInt64(shift))) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

extension BudRecord {
    /// A vault on disk keeps a trashed bud at `.trash/<where it was>`, so trashing `Kitchen/Shelf.md`
    /// leaves a folder `.trash/Kitchen` that the vault reads as a bud of its own. These records
    /// leave such a folder out when it only holds what was trashed from a bud still alive, or from
    /// the Inbox or the Archive; what was inside hangs from that live bud, or the top level.
    public static func withoutTrashFolders(_ records: [BudRecord]) -> [BudRecord] {
        let trash = ".trash/"
        let live = Set(records.filter { $0.place != .trash }.map(\.path))
        /// The live bud a trashed folder stands for, as nil inside an optional for the top level;
        /// nil when it stands for none.
        func counterpart(_ path: String) -> String?? {
            guard path.hasPrefix(trash), !path.hasSuffix(".md") else { return nil }
            let rest = String(path.dropFirst(trash.count))
            if live.contains(rest + ".md") { return .some(rest + ".md") }
            if live.contains(rest) { return .some(rest) }
            if rest == "Inbox" || rest == "Archive" { return .some(nil) }
            return nil
        }
        var stands: [String: String?] = [:]
        for record in records where record.place == .trash {
            if let live = counterpart(record.path) { stands[record.path] = live }
        }
        guard !stands.isEmpty else { return records }
        return records.compactMap { record in
            guard stands[record.path] == nil else { return nil }
            var record = record
            if let parent = record.parent, let live = stands[parent] { record.parent = live }
            return record
        }
    }
}

extension Tree {
    public func path(of id: UUID) -> String { id.uuidString }

    /// Where a bud lives. A bud in the Trash is `.trash`; one under a closed thread is `.archive`.
    public func place(of id: UUID) -> BudPlace {
        if trashed.contains(where: { branch in branch.buds.contains { $0.id == id } }) { return .trash }
        let chain = [id] + ancestors(of: id)
        if chain.contains(inboxID) { return .inbox }
        let top = chain.last { $0 != rootID }
        if let top, top != inboxID, bud(top)?.isDone == true { return .archive }
        return .everything
    }

    /// The record of one bud, with the place it is in.
    public func record(of bud: Bud, place: BudPlace) -> BudRecord {
        BudRecord(
            path: bud.path, parent: bud.parent == rootID ? nil : bud.parent.uuidString, title: bud.text,
            kind: bud.isTodo ? .todo : .note, state: bud.state, when: bud.when, due: bud.due,
            pinned: bud.pinned, created: bud.created, source: bud.source, body: bud.body, place: place
        )
    }

    /// Every bud as a record: Everything's tree in reading order, then the Inbox, then the Trash.
    public func records() -> [BudRecord] {
        let live = (walk(under: rootID) + walk(under: inboxID)).map { record(of: $0, place: place(of: $0.id)) }
        let gone = trashed.flatMap { branch in branch.buds.map { record(of: $0, place: .trash) } }
        return live + gone
    }

    /// A tree from a vault's records. Siblings keep the order the records came in. A branch in the
    /// Trash is one the records place there whose parent is not in the Trash with it; `trashedAt`
    /// says when each went in, for a branch the caller has seen before. `id` names the bud at a
    /// path, so one a vault moved can keep the id it had.
    public init(
        records: [BudRecord], trashedAt: (UUID) -> Date? = { _ in nil }, id: (String) -> UUID = Bud.id(forPath:)
    ) {
        func bud(from record: BudRecord, order: Double) -> Bud {
            let parent: UUID
            if let up = record.parent {
                parent = id(up)
            } else {
                parent = record.place == .inbox ? inboxID : rootID
            }
            return Bud(
                id: id(record.path), text: record.title,
                state: record.state ?? (record.kind == .todo ? .open : nil), parent: parent, order: order,
                body: record.body, when: record.when, due: record.due, pinned: record.pinned,
                created: record.created ?? Date(timeIntervalSince1970: 0), source: record.source
            )
        }
        var counters: [Bool: [UUID: Double]] = [false: [:], true: [:]]
        func next(under parent: UUID, trashed: Bool) -> Double {
            counters[trashed]![parent, default: 0] += 1
            return counters[trashed]![parent]!
        }
        var live: [Bud] = []
        var gone: [Bud] = []
        for record in records {
            let isGone = record.place == .trash
            let parent = record.parent.map(id) ?? (record.place == .inbox ? inboxID : rootID)
            let made = bud(from: record, order: next(under: parent, trashed: isGone))
            if isGone { gone.append(made) } else { live.append(made) }
        }
        let goneIDs = Set(gone.map(\.id))
        let heads = gone.filter { !goneIDs.contains($0.parent) }
        var branches: [TrashedBranch] = []
        for head in heads {
            var inside = Set([head.id])
            var members = [head]
            for bud in gone where bud.id != head.id {
                if inside.contains(bud.parent) {
                    inside.insert(bud.id)
                    members.append(bud)
                }
            }
            branches.append(TrashedBranch(at: trashedAt(head.id) ?? Date(), buds: members))
        }
        self.init(buds: live, trashed: branches)
    }
}
