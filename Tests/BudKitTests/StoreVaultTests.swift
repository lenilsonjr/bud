#if canImport(SwiftUI)
import XCTest
@testable import BudKit

/// The store over a memory vault: every change goes to the vault and the tree is what comes back.
@MainActor
final class StoreVaultTests: XCTestCase {
    private func loaded() async -> (BudStore, MemoryVault) {
        let vault = MemoryVault(tree: Tree.seed())
        let store = BudStore(vault: vault)
        await store.reload()
        return (store, vault)
    }

    private func titles(_ records: [BudRecord]) -> Set<String> { Set(records.map(\.title)) }

    func testTheStoreLoadsTheSnapshotIntoItsTree() async {
        let (store, vault) = await loaded()
        let records = try? await vault.snapshot()
        XCTAssertEqual(store.tree.buds.count, records?.filter { $0.place != .trash }.count)
        XCTAssertEqual(store.tree.children(of: rootID).first?.text, "Launch the newsletter")
    }

    func testAddingABudReachesTheVault() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        let planted = try XCTUnwrap(store.add("Book the printer", todo: true, under: thread.id))
        await store.settle()
        let records = try await vault.snapshot()
        let record = try XCTUnwrap(records.first { $0.path == planted.id.uuidString })
        XCTAssertEqual(record.title, "Book the printer")
        XCTAssertEqual(record.kind, .todo)
        XCTAssertEqual(record.parent, thread.id.uuidString)
        XCTAssertEqual(store.tree.bud(planted.id)?.text, "Book the printer")
    }

    func testARenameRewritesTheLinksToTheBudAndUndoPutsThemBack() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        let other = try XCTUnwrap(store.tree.children(of: rootID).dropFirst().first)
        store.setBody(other.id, "See [[\(thread.text)|the launch]].")
        store.update(thread.id, text: "Ship the newsletter", todo: thread.isTodo)
        await store.settle()
        XCTAssertEqual(store.tree.bud(other.id)?.body, "See [[Ship the newsletter|the launch]].")
        XCTAssertEqual(store.toasts.current?.action.message, "Updated links in 1 bud")
        let records = try await vault.snapshot()
        XCTAssertEqual(records.first { $0.path == other.id.uuidString }?.body, "See [[Ship the newsletter|the launch]].")
        store.toasts.current?.action.undo?()
        for _ in 0..<100 where store.tree.bud(thread.id)?.text != thread.text { await Task.yield() }
        await store.settle()
        XCTAssertEqual(store.tree.bud(thread.id)?.text, thread.text)
        XCTAssertEqual(store.tree.bud(other.id)?.body, "See [[\(thread.text)|the launch]].")
    }

    func testATagRenameUndoneAtOnceStillPutsEveryBudBack() async throws {
        let (store, vault) = await loaded()
        let a = try XCTUnwrap(store.tree.children(of: rootID).first)
        let b = try XCTUnwrap(store.tree.children(of: rootID).dropFirst().first)
        store.addTag(a.id, "home")
        store.setBody(b.id, "Milk #home")
        await store.settle()
        store.renameTag("home", to: "house")
        XCTAssertEqual(store.tree.bud(a.id)?.tags, ["house"])
        // Undo before the rename has reached the vault: the undo waits for it.
        store.toasts.current?.action.undo?()
        for _ in 0..<100 where store.tree.bud(b.id)?.body != "Milk #home" { await Task.yield() }
        await store.settle()
        XCTAssertEqual(store.tree.bud(a.id)?.tags, ["home"])
        XCTAssertEqual(store.tree.bud(b.id)?.body, "Milk #home")
        let records = try await vault.snapshot()
        XCTAssertEqual(records.first { $0.path == a.id.uuidString }?.tags, ["home"])
    }

    func testRemovingATagTheBodyAlsoHasCanBeUndone() async throws {
        let (store, _) = await loaded()
        let a = try XCTUnwrap(store.tree.children(of: rootID).first)
        store.addTag(a.id, "home")
        store.setBody(a.id, "#home too")
        await store.settle()
        store.removeTag(a.id, "home")
        await store.settle()
        XCTAssertEqual(store.tree.bud(a.id)?.tags, [])
        store.toasts.current?.action.undo?()
        for _ in 0..<100 where store.tree.bud(a.id)?.tags != ["home"] { await Task.yield() }
        await store.settle()
        XCTAssertEqual(store.tree.bud(a.id)?.tags, ["home"])
    }

    func testUndoingARemovePutsTheTagBackInItsPlace() async throws {
        let (store, vault) = await loaded()
        let a = try XCTUnwrap(store.tree.children(of: rootID).first)
        store.addTag(a.id, "home")
        store.addTag(a.id, "errands")
        await store.settle()
        store.removeTag(a.id, "home")
        await store.settle()
        XCTAssertEqual(store.tree.bud(a.id)?.tags, ["errands"])
        store.toasts.current?.action.undo?()
        for _ in 0..<100 where store.tree.bud(a.id)?.tags != ["home", "errands"] { await Task.yield() }
        await store.settle()
        XCTAssertEqual(store.tree.bud(a.id)?.tags, ["home", "errands"])
        let records = try await vault.snapshot()
        XCTAssertEqual(records.first { $0.path == a.id.uuidString }?.tags, ["home", "errands"])
    }

    func testATickedTagFollowsARename() async throws {
        let (store, _) = await loaded()
        let a = try XCTUnwrap(store.tree.children(of: rootID).first)
        store.addTag(a.id, "home")
        store.addTag(a.id, "house")
        await store.settle()
        store.canvasFacets = [.openTodos, .tag("Home"), .tag("house")]
        store.renameTag("home", to: "house")
        XCTAssertEqual(store.canvasFacets.map(\.name), ["Open to-dos", "#house"])
        store.renameTag("house", to: "place")
        XCTAssertEqual(store.canvasFacets.map(\.name), ["Open to-dos", "#place"])
        store.toasts.current?.action.undo?()
        for _ in 0..<100 where store.canvasFacets.map(\.name) != ["Open to-dos", "#house"] { await Task.yield() }
        XCTAssertEqual(store.canvasFacets.map(\.name), ["Open to-dos", "#house"])
        await store.settle()
    }

    func testALinkedRowTakesItsBudsNewTitleAndGoesWithTheBud() async throws {
        let (store, _) = await loaded()
        let a = try XCTUnwrap(store.tree.children(of: rootID).first)
        let facet = LensFacet.linked(a.id, title: a.text)
        store.canvasFacets = [facet]
        store.update(a.id, text: "Renamed here", todo: a.isTodo)
        await store.settle()
        XCTAssertEqual(store.facetName(facet), "Linked to Renamed here")
        store.trash(a.id)
        await store.settle()
        XCTAssertEqual(store.canvasFacets, [facet], "a bud in the Trash can come back")
        store.freshStart(sample: false)
        await store.settle()
        XCTAssertEqual(store.canvasFacets, [], "a bud gone for good takes its row with it")
    }

    func testAFreshStartEmptiesTheVaultAndTheTrash() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        store.trash(thread.id)
        await store.settle()
        XCTAssertFalse(store.tree.trashed.isEmpty)
        store.center = try XCTUnwrap(store.tree.children(of: rootID).first?.id)
        store.freshStart(sample: false)
        await store.settle()
        XCTAssertTrue(store.tree.buds.isEmpty)
        XCTAssertTrue(store.tree.trashed.isEmpty)
        XCTAssertEqual(store.center, rootID)
        let records = try await vault.snapshot()
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(store.toasts.current?.action.message, "Started over")
        XCTAssertNil(store.toasts.current?.action.undo)
    }

    func testAFreshStartCanPlantTheSampleWorldAgain() async throws {
        let vault = MemoryVault(tree: Tree())
        let store = BudStore(vault: vault)
        await store.reload()
        XCTAssertTrue(store.tree.buds.isEmpty)
        store.freshStart(sample: true)
        await store.settle()
        XCTAssertEqual(store.tree.children(of: rootID).first?.text, "Launch the newsletter")
        let records = try await vault.snapshot()
        XCTAssertEqual(titles(records), titles(Tree.seed().records()))
        XCTAssertEqual(store.toasts.current?.action.message, "Started over with the sample vault")
    }

    func testACaptureLandsInTheVaultsInbox() async throws {
        let (store, vault) = await loaded()
        let bud = try XCTUnwrap(store.capture("Buy stamps", source: "mac"))
        await store.settle()
        let record = try await vault.snapshot().first { $0.path == bud.id.uuidString }
        XCTAssertEqual(record?.place, .inbox)
        XCTAssertEqual(record?.source, "mac")
        XCTAssertEqual(store.tree.inbox().last?.text, "Buy stamps")
    }

    func testABudPlantedOnEverythingIsATopLevelFileNotAnInboxOne() async throws {
        let (store, vault) = await loaded()
        let bud = try XCTUnwrap(store.plant("A new thread", todo: false, at: PlantTarget.forCenter(rootID)))
        await store.settle()
        let record = try await vault.snapshot().first { $0.path == bud.id.uuidString }
        XCTAssertNotNil(record)
        XCTAssertNil(record?.parent, "Everything is the top level")
        XCTAssertNotEqual(record?.place, .inbox)
        XCTAssertTrue(store.tree.children(of: rootID).contains { $0.id == bud.id })
    }

    func testASwapReachesTheVaultAndUndoTradesBack() async throws {
        let (store, vault) = await loaded()
        let threads = store.tree.children(of: rootID).map(\.id)
        XCTAssertTrue(store.swap(threads[0], threads[1]))
        await store.settle()
        var top = try await vault.snapshot().filter { $0.parent == nil && $0.place == .everything }.map(\.path)
        XCTAssertEqual(Array(top.prefix(2)), [threads[1].uuidString, threads[0].uuidString])
        XCTAssertEqual(store.toasts.current?.action.message, "Swapped")
        store.toasts.current?.action.undo?()
        try await Task.sleep(nanoseconds: 50_000_000)
        await store.settle()
        top = try await vault.snapshot().filter { $0.parent == nil && $0.place == .everything }.map(\.path)
        XCTAssertEqual(Array(top.prefix(2)), [threads[0].uuidString, threads[1].uuidString])
        XCTAssertFalse(store.swap(threads[0], threads[0]))
    }

    func testMovingLaterTradesPlacesWithTheNextSiblingAndStopsAtTheEnd() async throws {
        let (store, vault) = await loaded()
        let threads = store.tree.children(of: rootID).map(\.id)
        XCTAssertTrue(store.shift(threads[0], by: 1))
        await store.settle()
        let top = try await vault.snapshot().filter { $0.parent == nil && $0.place == .everything }.map(\.path)
        XCTAssertEqual(Array(top.prefix(2)), [threads[1].uuidString, threads[0].uuidString])
        XCTAssertEqual(store.toasts.current?.action.message, "Moved later")
        XCTAssertFalse(store.shift(threads[1], by: -1), "Already first")
    }

    func testEditingTickingAndPinningReachTheVault() async throws {
        let (store, vault) = await loaded()
        let verify = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Verify the address" })
        store.update(verify.id, text: "Verify the sender address", todo: true)
        store.setBody(verify.id, "Check the records.")
        store.setPinned(verify.id, true)
        store.tick(verify.id)
        await store.settle()
        let record = try await vault.snapshot().first { $0.path == verify.id.uuidString }
        XCTAssertEqual(record?.title, "Verify the sender address")
        XCTAssertEqual(record?.body, "Check the records.")
        XCTAssertEqual(record?.pinned, true)
        XCTAssertEqual(record?.state, .done)
        XCTAssertEqual(store.tree.bud(verify.id)?.state, .done)
        store.tick(verify.id)
        await store.settle()
        let reopened = try await vault.snapshot().first { $0.path == verify.id.uuidString }
        XCTAssertEqual(reopened?.state, .open)
    }

    func testMoveReachesTheVaultAndUndoMovesItBack() async throws {
        let (store, vault) = await loaded()
        let name = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Pick a name" })
        let roadmap = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
        XCTAssertTrue(store.move(name.id, under: roadmap.id))
        await store.settle()
        let moved = try await vault.snapshot().first { $0.path == name.id.uuidString }
        XCTAssertEqual(moved?.parent, roadmap.id.uuidString)
        store.toasts.undo()
        try await Task.sleep(for: .milliseconds(100))
        await store.settle()
        let back = try await vault.snapshot().first { $0.path == name.id.uuidString }
        XCTAssertEqual(back?.parent, name.parent.uuidString)
    }

    func testTrashRestoreAndUndoGoThroughTheVault() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Launch the newsletter" })
        let before = store.tree
        store.trash(thread.id)
        await store.settle()
        XCTAssertNil(store.tree.bud(thread.id))
        XCTAssertEqual(store.tree.trashed.count, 1)
        var records = try await vault.snapshot()
        XCTAssertEqual(records.first { $0.path == thread.id.uuidString }?.place, .trash)
        XCTAssertEqual(store.toasts.current?.action.message, "Trashed Launch the newsletter")

        store.restore(thread.id)
        await store.settle()
        XCTAssertEqual(store.tree, before)
        XCTAssertEqual(store.toasts.current?.action.message, "Restored Launch the newsletter")
        records = try await vault.snapshot()
        XCTAssertEqual(records.first { $0.path == thread.id.uuidString }?.place, .everything)

        store.toasts.undo()
        try await Task.sleep(for: .milliseconds(100))
        await store.settle()
        XCTAssertNil(store.tree.bud(thread.id))
        XCTAssertEqual(store.tree.trashed.count, 1)
    }

    func testDeletingForeverAndEmptyingTheTrashReachTheVault() async throws {
        let (store, vault) = await loaded()
        let roadmap = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Q4 roadmap" })
        let language = try XCTUnwrap(store.tree.children(of: rootID).first { $0.text == "Learn a language" })
        store.trash(roadmap.id)
        store.trash(language.id)
        store.deleteForever(roadmap.id)
        await store.settle()
        XCTAssertEqual(store.tree.trashed.map(\.id), [language.id])
        store.emptyTrash()
        await store.settle()
        XCTAssertTrue(store.tree.trashed.isEmpty)
        let records = try await vault.snapshot()
        XCTAssertEqual(records.filter { $0.place == .trash }.count, 0)
    }

    func testAWatchCallbackReloadsTheTree() async throws {
        let (store, vault) = await loaded()
        try await Task.sleep(for: .milliseconds(100))
        await vault.externalChange { $0.add("Added in the folder", todo: false, under: rootID) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(store.tree.children(of: rootID).first { $0.text == "Added in the folder" })
    }

    func testTheCenterStaysPutAcrossReloadsUntilItsBudIsGone() async throws {
        let (store, vault) = await loaded()
        let name = try XCTUnwrap(store.tree.walk(under: rootID).first { $0.text == "Pick a name" })
        store.center = name.id
        await vault.externalChange { $0.add("Added in the folder", todo: false, under: rootID) }
        await store.reload()
        XCTAssertEqual(store.center, name.id)
        XCTAssertNotNil(store.tree.children(of: rootID).first { $0.text == "Added in the folder" })
        await vault.externalChange { $0.remove(name.id) }
        await store.reload()
        XCTAssertEqual(store.center, rootID)
    }

    func testTheFileStoreStillWritesTheJSONFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = BudStore(fileURL: url)
        let bud = try XCTUnwrap(store.add("Plan the spring issue", todo: false, under: rootID))
        await store.settle()
        let tree = try JSONDecoder().decode(Tree.self, from: Data(contentsOf: url))
        XCTAssertEqual(tree.bud(bud.id)?.text, "Plan the spring issue")
        let again = BudStore(fileURL: url)
        XCTAssertEqual(again.tree.bud(bud.id)?.text, "Plan the spring issue")
    }

    // MARK: planting from a source

    func testTheSoilFoldStaysFoldedOnThisDevice() async {
        let (store, _) = await loaded()
        store.soilFolded = true
        let (again, _) = await loaded()
        XCTAssertTrue(again.soilFolded)
        again.soilFolded = false
        let (third, _) = await loaded()
        XCTAssertFalse(third.soilFolded)
    }

    func testShowingTheSoilWritesNothing() async throws {
        let (store, vault) = await loaded()
        let before = try await vault.snapshot()
        store.sources = SourceAccount.samples()
        XCTAssertEqual(store.roots().count, 4)
        await store.reload()
        await store.settle()
        let after = try await vault.snapshot()
        XCTAssertEqual(after, before)
    }

    private let account = SourceAccount(id: "work", kind: .mail, name: "Work mail")
    private let item = SourceItem(id: "M-7", title: "Lease renewal draft", detail: "Harbor Lettings", todo: true)

    func testDroppingOnABudPlantsItAsAChild() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        let bud = store.plant(item, from: account, at: .under(thread.id))
        await store.settle()
        XCTAssertEqual(store.tree.bud(bud.id)?.parent, thread.id)
        XCTAssertEqual(store.toasts.current?.action.message, "Planted in \(thread.text), from Work mail")
        let record = try await vault.snapshot().first { $0.from == "mail:M-7" }
        XCTAssertEqual(record?.title, "Lease renewal draft")
        XCTAssertEqual(record?.kind, .todo)
        XCTAssertEqual(record?.parent, thread.id.uuidString)
    }

    func testDroppingOnEmptyCanvasPlantsItInTheInbox() async throws {
        let (store, vault) = await loaded()
        let bud = store.plant(item, from: account, at: .inbox)
        await store.settle()
        XCTAssertEqual(store.tree.bud(bud.id)?.parent, inboxID)
        XCTAssertEqual(store.toasts.current?.action.message, "Planted in Inbox, from Work mail")
        let record = try await vault.snapshot().first { $0.from == "mail:M-7" }
        XCTAssertEqual(record?.place, .inbox)
    }

    func testUndoTakesThePlantedBudAway() async throws {
        let (store, vault) = await loaded()
        let bud = store.plant(item, from: account, at: .inbox)
        await store.settle()
        store.toasts.current?.action.undo?()
        for _ in 0..<100 where store.tree.bud(bud.id) != nil { await Task.yield() }
        await store.settle()
        XCTAssertNil(store.tree.bud(bud.id))
        let records = try await vault.snapshot()
        XCTAssertNil(records.first { $0.from == "mail:M-7" })
    }

    func testPlantingAgainGoesToTheBudItMade() async throws {
        let (store, vault) = await loaded()
        let thread = try XCTUnwrap(store.tree.children(of: rootID).first)
        let first = store.plant(item, from: account, at: .under(thread.id))
        await store.settle()
        store.center = rootID
        let again = store.plant(item, from: account, at: .inbox)
        await store.settle()
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(store.center, thread.id)
        XCTAssertEqual(store.toasts.current?.action.message, "Already planted in \(thread.text)")
        let records = try await vault.snapshot()
        XCTAssertEqual(records.filter { $0.from == "mail:M-7" }.count, 1)
    }

    // MARK: keeping planted buds live

    func testAMovedEventMovesItsPlantedBudAndMarksIt() async throws {
        let (store, vault) = await loaded()
        let uid = UUID().uuidString
        let first = Date(timeIntervalSinceNow: 3 * 86_400)
        let calendar = SourceAccount(id: "cal", kind: .calendar, name: "Home")
        let bud = store.plant(SourceItem(id: uid, title: "Flat viewing", date: first), from: calendar, at: .inbox)
        await store.settle()
        XCTAssertNotNil(store.tree.bud(bud.id)?.when, "a planted event starts with its day")

        let moved = CalDAV.stamp(Date(timeIntervalSinceNow: 5 * 86_400))
        let token = "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:propstat><d:prop><d:sync-token>1</d:sync-token></d:prop></d:propstat></d:response></d:multistatus>"
        let report = "<d:multistatus xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:response><d:propstat><d:prop><c:calendar-data>BEGIN:VEVENT\nUID:\(uid)\nSUMMARY:Flat viewing\nDTSTART:\(moved)\nEND:VEVENT</c:calendar-data></d:prop></d:propstat></d:response></d:multistatus>"
        let soil = SourceStore(
            defaults: UserDefaults(suiteName: "live-\(UUID().uuidString)")!, tokens: MemoryTokens(),
            http: ScriptedHTTP([(token, 207), (report, 207)]))
        soil.deviceName = BudStore.deviceName
        await soil.connectCalendar(
            name: "Home", server: URL(string: "https://cal.example.org/")!, user: "sam", password: "p",
            calendar: URL(string: "https://cal.example.org/home/")!)
        await store.keepLive(soil)
        await store.settle()
        let now = try XCTUnwrap(store.tree.bud(bud.id))
        XCTAssertEqual(now.when.map { Calendar.current.startOfDay(for: $0) }, Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: 5 * 86_400)))
        XCTAssertTrue(now.fromState?.hasPrefix("moved ") ?? false)
        XCTAssertEqual(store.mark(of: now)?.device, BudStore.deviceName)
        let record = try await vault.snapshot().first { $0.from == "calendar:\(uid)" }
        XCTAssertTrue(record?.fromState?.hasPrefix("moved ") ?? false)
    }
}
#endif
