import AppKit
import SwiftUI
import UserNotifications

enum Kind: String, CaseIterable {
    case review, authored, assigned, mentioned, issueAssigned, issueAuthored, issueMentioned

    var pr: Bool { !rawValue.hasPrefix("issue") }

    var title: String {
        switch self {
        case .review: return "Review requested"
        case .authored, .issueAuthored: return "Yours"
        case .assigned, .issueAssigned: return "Assigned"
        case .mentioned, .issueMentioned: return "Mentioned"
        }
    }

    var query: String {
        let who: String
        switch self {
        case .review: who = "review-requested:@me"
        case .authored, .issueAuthored: who = "author:@me"
        case .assigned, .issueAssigned: who = "assignee:@me"
        case .mentioned, .issueMentioned: who = "mentions:@me"
        }
        return "is:open archived:false is:\(pr ? "pr" : "issue") \(who)"
    }

    // Your own pull requests and issues arrive because you made them, so they don't notify.
    var alert: Alert? {
        switch self {
        case .review: return .reviewRequested
        case .assigned, .issueAssigned: return .assigned
        case .mentioned, .issueMentioned: return .mentioned
        case .authored, .issueAuthored: return nil
        }
    }
}

struct Item: Identifiable {
    let url: String, number: Int, title: String, repo: String, updated: Date
    let draft: Bool
    let labels: [String]
    let review: String?
    let checks: String?
    let kind: Kind
    var id: String { url }
}

struct Runner: Identifiable {
    let repo: String, name: String, online: Bool, busy: Bool, labels: [String]
    var job: JobRef?
    var id: String { repo + "/" + name }
}

struct JobRef { let name: String, url: String, id: Int, runID: Int }

struct JobInfo: Decodable {
    struct Step: Decodable {
        let number: Int, name: String, status: String
        let conclusion: String?, started_at: Date?, completed_at: Date?
    }
    let id: Int, name: String, html_url: String, status: String
    let conclusion: String?, started_at: Date?, head_branch: String?, runner_name: String?, steps: [Step]?
}

struct RunInfo: Decodable {
    struct Actor: Decodable { let login: String }
    let display_title: String, actor: Actor?
}

struct Annotation: Decodable {
    let path: String, start_line: Int, annotation_level: String, message: String, title: String?
}

// What the run detail view shows. CPU, memory and the live log only exist for runners on this Mac.
struct Detail {
    let runner: Runner
    var job: JobInfo?
    var run: RunInfo?
    var annotations: [Annotation] = []
    var local = false
    var cpu: Double?
    var memory: Double?
    var log: [String] = []
}

struct Snapshot {
    var items: [Item] = []
    var runners: [Runner] = []
    var runs: [Run] = []
    var error: String?
    var updated: Date?
}

struct Search: Decodable {
    struct Node: Decodable {
        struct Repo: Decodable { let nameWithOwner: String; struct Label: Decodable { let name: String } }
        struct Commits: Decodable { let nodes: [C] }
        struct C: Decodable { let commit: Commit }
        struct Commit: Decodable { let statusCheckRollup: Rollup? }
        struct Rollup: Decodable { let state: String }
        struct Labels: Decodable { let nodes: [Repo.Label] }
        let number: Int, title: String, url: String, updatedAt: Date, repository: Repo, labels: Labels
        let isDraft: Bool?, reviewDecision: String?, commits: Commits?
    }
    struct Result: Decodable { let nodes: [Node] }
    let data: [String: Result]
}

struct RunnerList: Decodable {
    struct R: Decodable { let name: String, status: String, busy: Bool, labels: [L] }
    struct L: Decodable { let name: String }
    let runners: [R]
}

struct RunList: Decodable {
    struct Actor: Decodable { let login: String }
    struct Run: Decodable {
        let id: Int, name: String, display_title: String, head_branch: String?, status: String, conclusion: String?
        let html_url: String, updated_at: Date, run_started_at: Date?, actor: Actor?
    }
    let workflow_runs: [Run]
}

struct Run: Identifiable {
    let id: Int, repo: String, workflow: String, title: String, branch: String?, status: String, conclusion: String?
    let url: String, updated: Date, started: Date?, actor: String?
}

struct JobList: Decodable {
    struct Job: Decodable { let id: Int, name: String, status: String, runner_name: String?, html_url: String }
    let jobs: [Job]
}

struct RepoInfo: Decodable {
    struct Perm: Decodable { let admin: Bool }
    let full_name: String, archived: Bool, permissions: Perm?
}

struct Fail: Error { let message: String }

// GitHub's Invertocat (Octicons mark-github). NSImage reads SVG from macOS 14.
let githubMark = NSImage(data: Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>"#.utf8))!

enum Alert: String, CaseIterable {
    case reviewRequested, mentioned, assigned, labeled, checksFailed, checksPassed, approved, changesRequested, updated
    case runnerOffline, runnerOnline, jobStarted, jobFinished, runFailed, runPassed

    var title: String {
        switch self {
        case .reviewRequested: return "Review requested"
        case .mentioned: return "Mentioned"
        case .assigned: return "Assigned"
        case .labeled: return "Watched label added"
        case .checksFailed: return "Checks failed"
        case .checksPassed: return "Checks passed"
        case .approved: return "Approved"
        case .changesRequested: return "Changes requested"
        case .updated: return "Other updates"
        case .runnerOffline: return "Runner went offline"
        case .runnerOnline: return "Runner came online"
        case .jobStarted: return "Job started"
        case .jobFinished: return "Job finished"
        case .runFailed: return "Run failed"
        case .runPassed: return "Run passed"
        }
    }

    // Updates fire on your own pushes and comments too, and passes and starts are routine, so they start off.
    var onByDefault: Bool { ![.updated, .jobStarted, .runPassed].contains(self) }
}

// Comma-separated sets in UserDefaults, so @AppStorage can hold them.
func stored(_ key: String) -> Set<String> {
    Set((UserDefaults.standard.string(forKey: key) ?? "").split(separator: ",").map(String.init))
}

// A repository's own notification setting, else its organization's, else the global one.
func setting(_ key: String, _ repo: String) -> String {
    let d = UserDefaults.standard
    return d.string(forKey: "\(key).\(repo)") ?? d.string(forKey: "\(key).\(owner(repo))") ?? d.string(forKey: key)!
}

func shows(_ repo: String) -> Bool {
    let hidden = stored("hidden")
    return !hidden.contains(repo) && !hidden.contains(owner(repo))
}

// One row per issue or PR: the first enabled kind it matched, in Kind order.
func visible(_ items: [Item]) -> [Item] {
    let kinds = stored("kinds")
    var seen = Set<String>()
    return items.filter { kinds.contains($0.kind.rawValue) && shows($0.repo) && seen.insert($0.url).inserted }
}

// A key press cut from a recording of a real keyboard. The app plays it itself because macOS plays notification sounds at the
// alert volume, which can be 0.
let keyClick = NSSound(contentsOf: Bundle.main.url(forResource: "notify", withExtension: "wav")!, byReference: true)!

func ago(_ d: Date) -> String {
    let s = -d.timeIntervalSinceNow
    if s < 3600 { return "\(max(1, Int(s / 60)))m" }
    if s < 86400 { return "\(Int(s / 3600))h" }
    return "\(Int(s / 86400))d"
}

let machSeconds: Double = { var t = mach_timebase_info(); mach_timebase_info(&t); return Double(t.numer) / Double(t.denom) / 1e9 }()

// One sysctl lists every process with its parent; running ps every two seconds would cost far more.
func allProcesses() -> [(pid: Int32, ppid: Int32)] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
    var size = 0
    sysctl(&mib, 3, nil, &size, nil, 0)
    var kp = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
    size = kp.count * MemoryLayout<kinfo_proc>.stride
    sysctl(&mib, 3, &kp, &size, nil, 0)
    return kp.prefix(size / MemoryLayout<kinfo_proc>.stride).map { ($0.kp_proc.p_pid, $0.kp_eproc.e_ppid) }
}

func processPath(_ pid: Int32) -> String? {
    var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
}

// CPU seconds the kernel has billed the process, and its memory as Activity Monitor counts it.
func usage(_ pid: Int32) -> (time: Double, footprint: Double)? {
    var i = rusage_info_v2()
    let r = withUnsafeMutablePointer(to: &i) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
    }
    return r == 0 ? (Double(i.ri_user_time + i.ri_system_time) * machSeconds, Double(i.ri_phys_footprint)) : nil
}

// A runner's install folder holds a .runner file naming it and its repo.
func runnerIdentity(_ root: String) -> (name: String, url: String)? {
    guard let data = FileManager.default.contents(atPath: root + "/.runner") else { return nil }
    // The runner writes it with a byte order mark, which JSONSerialization rejects.
    let json = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
    guard let d = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
          let name = d["agentName"] as? String, let url = d["gitHubUrl"] as? String else { return nil }
    return (name, url)
}

// GitHub only serves a job's log once it finishes, but the runner writes the running step's output to _diag/pages as it goes.
func liveLog(_ root: String) -> [String] {
    let dir = root + "/_diag/pages", fm = FileManager.default
    func modified(_ p: String) -> Date { (try? fm.attributesOfItem(atPath: p)[.modificationDate] as? Date) ?? .distantPast }
    guard let names = try? fm.contentsOfDirectory(atPath: dir),
          let newest = names.map({ dir + "/" + $0 }).max(by: { modified($0) < modified($1) }),
          let h = FileHandle(forReadingAtPath: newest) else { return [] }
    defer { try? h.close() }
    let end = h.seekToEndOfFile(), window: UInt64 = 32768
    h.seek(toFileOffset: end > window ? end - window : 0)
    var lines = String(decoding: h.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
    if end > window { lines.removeFirst() }
    return lines.suffix(300).compactMap { line in
        var l = line.drop { $0 == "\u{FEFF}" }
        // Each line starts with a timestamp like 2026-10-26T08:24:47.4931120Z.
        if l.count >= 29, l[l.index(l.startIndex, offsetBy: 27)] == "Z" { l = l.dropFirst(29) }
        if l.hasPrefix("##[endgroup]") { return nil }
        if l.hasPrefix("##[group]") { l = l.dropFirst(9) }
        return l.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
    }
}

func duration(_ s: TimeInterval) -> String {
    let t = max(0, Int(s))
    if t < 60 { return "\(t)s" }
    if t < 3600 { return String(format: "%dm %02ds", t / 60, t % 60) }
    return String(format: "%dh %02dm", t / 3600, t / 60 % 60)
}

@MainActor
final class GitBar: NSObject, NSApplicationDelegate, NSPopoverDelegate, ObservableObject, UNUserNotificationCenterDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let popover = NSPopover()
    let session = URLSession(configuration: .ephemeral)
    @Published var shown = Snapshot()
    @Published var refreshing = false
    var latest = Snapshot()
    // Read from `gh auth token` into memory only; cleared on 401 so the next poll asks gh again.
    var token: String?
    var runnerRepos: [String] = []
    var discovered = Date.distantPast
    var inFlight = false
    var outsideClick: Any?
    var etags: [String: (etag: String, data: Data)] = [:]
    @Published var detail: Detail?
    var detailTimer: Timer?
    var detailTicks = 0
    var worker: (pid: Int32, root: String)?
    var lastCPU: (time: Double, at: Date)?
    var identities: [String: (name: String, url: String)] = [:]

    func applicationDidFinishLaunching(_ n: Notification) {
        UserDefaults.standard.register(defaults: ["kinds": "review,authored,assigned,issueAssigned", "hidden": "", "notify": true,
                                                 "alerts": Alert.allCases.filter(\.onByDefault).map(\.rawValue).joined(separator: ","), "muted": "", "watchLabels": "",
                                                 "content": "source,event,details,thread"])
        // "New pull request or issue" became one switch per reason.
        if stored("alerts").contains("newItem") {
            UserDefaults.standard.set(stored("alerts").subtracting(["newItem"]).union(["mentioned", "assigned"]).sorted().joined(separator: ","), forKey: "alerts")
        }
        let mark = githubMark.copy() as! NSImage
        mark.size = NSSize(width: 16, height: 16)
        mark.isTemplate = true
        mark.accessibilityDescription = "osk/gn"
        item.button?.image = mark
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: Panel(m: self))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        UNUserNotificationCenter.current().delegate = self
        if UserDefaults.standard.bool(forKey: "notify") { askToNotify() }
        Task { await refresh() }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in Task { await self?.refresh() } }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
    }

    func askToNotify() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func readToken() throws -> String {
        // Apps opened from Finder don't inherit the shell's PATH.
        guard let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first(where: FileManager.default.isExecutableFile) else {
            throw Fail(message: "Install the GitHub CLI: brew install gh")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gh)
        p.arguments = ["auth", "token", "-h", "github.com"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        let t = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.terminationStatus == 0, !t.isEmpty else { throw Fail(message: "Sign in to the GitHub CLI: gh auth login") }
        return t
    }

    func api<T: Decodable>(_ path: String, graphQL: String? = nil) async throws -> T {
        if token == nil { token = try readToken() }
        var r = URLRequest(url: URL(string: "https://api.github.com/" + path)!, cachePolicy: .reloadIgnoringLocalCacheData)
        r.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")
        if let graphQL {
            r.httpMethod = "POST"
            r.httpBody = try JSONEncoder().encode(["query": graphQL])
        } else if let c = etags[path] {
            r.setValue(c.etag, forHTTPHeaderField: "If-None-Match")
        }
        var (data, resp) = try await session.data(for: r)
        let http = resp as! HTTPURLResponse
        if http.statusCode == 401 { token = nil; throw Fail(message: "GitHub rejected the gh token. Run gh auth login") }
        // GitHub doesn't count a 304 against the rate limit, which is what lets every repo's runs be polled each minute.
        if http.statusCode == 304, let c = etags[path] {
            data = c.data
        } else {
            guard http.statusCode == 200 else { throw Fail(message: "GitHub returned \(http.statusCode) for \(path)") }
            if graphQL == nil, let tag = http.value(forHTTPHeaderField: "ETag") { etags[path] = (tag, data) }
        }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(T.self, from: data)
    }

    func fetchItems() async throws -> [Item] {
        let fields = "number title url updatedAt repository { nameWithOwner } labels(first: 20) { nodes { name } }"
        let pr = "... on PullRequest { \(fields) isDraft reviewDecision commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } }"
        let q = "{" + Kind.allCases.map {
            "\($0.rawValue): search(query: \"\($0.query)\", type: ISSUE, first: 50) { nodes { \(pr) ... on Issue { \(fields) } } }"
        }.joined(separator: " ") + "}"
        let s: Search = try await api("graphql", graphQL: q)
        return Kind.allCases.flatMap { k in
            (s.data[k.rawValue]?.nodes ?? []).map {
                Item(url: $0.url, number: $0.number, title: $0.title, repo: $0.repository.nameWithOwner, updated: $0.updatedAt,
                     draft: $0.isDraft ?? false, labels: $0.labels.nodes.map(\.name), review: $0.reviewDecision,
                     checks: $0.commits?.nodes.first?.commit.statusCheckRollup?.state, kind: k)
            }
        }
    }

    // Org runners need admin:org, which this gh token doesn't have, so only repos you admin are checked.
    // Most have no runners; finding the ones that do takes a call per repo, so it's redone every 6 hours, not every poll.
    func discoverRunnerRepos() async throws {
        var repos: [String] = []
        for page in 1... {
            let list: [RepoInfo] = try await api("user/repos?per_page=100&page=\(page)")
            repos += list.filter { !$0.archived && $0.permissions?.admin == true }.map(\.full_name)
            if list.count < 100 { break }
        }
        var found: [String] = []
        for r in repos {
            if let l: RunnerList = try? await api("repos/\(r)/actions/runners"), !l.runners.isEmpty { found.append(r) }
        }
        runnerRepos = found
        discovered = Date()
    }

    func fetchRunners() async throws -> [Runner] {
        if -discovered.timeIntervalSinceNow > 6 * 3600 { try await discoverRunnerRepos() }
        var out: [Runner] = []
        for repo in runnerRepos {
            guard let l: RunnerList = try? await api("repos/\(repo)/actions/runners") else { continue }
            out += l.runners.map {
                Runner(repo: repo, name: $0.name, online: $0.status == "online", busy: $0.busy,
                       labels: $0.labels.map(\.name).filter { $0 != "self-hosted" })
            }
        }
        // The runners API doesn't say what a busy runner is doing; the in-progress runs' jobs do.
        for repo in Set(out.filter(\.busy).map(\.repo)) {
            let runs: RunList = try await api("repos/\(repo)/actions/runs?status=in_progress&per_page=20")
            for run in runs.workflow_runs {
                let jobs: JobList = try await api("repos/\(repo)/actions/runs/\(run.id)/jobs?filter=latest&per_page=100")
                for j in jobs.jobs where j.status == "in_progress" {
                    if let i = out.firstIndex(where: { $0.repo == repo && $0.name == j.runner_name }) {
                        out[i].job = JobRef(name: "\(run.name) · \(j.name)", url: j.html_url, id: j.id, runID: run.id)
                    }
                }
            }
        }
        return out
    }

    // Runs come from the repos of your pull requests and your runners; issue-only repos are left out to keep the calls down.
    func fetchRuns(_ items: [Item], _ runners: [Runner]) async -> [Run] {
        let repos = Set(items.filter(\.kind.pr).map(\.repo) + runners.map(\.repo)).filter(shows)
        var out: [Run] = []
        for repo in repos.sorted() {
            guard let l: RunList = try? await api("repos/\(repo)/actions/runs?per_page=10") else { continue }
            out += l.workflow_runs.map {
                Run(id: $0.id, repo: repo, workflow: $0.name, title: $0.display_title, branch: $0.head_branch, status: $0.status,
                    conclusion: $0.conclusion, url: $0.html_url, updated: $0.updated_at, started: $0.run_started_at, actor: $0.actor?.login)
            }
        }
        return out
    }

    // A run opens on its running job, or its first job once it's done, in the same detail view a busy runner uses.
    func openRun(_ run: Run) async {
        struct Jobs: Decodable { let jobs: [JobInfo] }
        guard let list: Jobs = try? await api("repos/\(run.repo)/actions/runs/\(run.id)/jobs?filter=latest&per_page=100"),
              let job = list.jobs.first(where: { $0.status == "in_progress" }) ?? list.jobs.first else {
            open(run.url)
            return
        }
        let ref = JobRef(name: "\(run.workflow) · \(job.name)", url: job.html_url, id: job.id, runID: run.id)
        openDetail(Runner(repo: run.repo, name: job.runner_name ?? "", online: true, busy: job.status == "in_progress", labels: [], job: ref))
    }

    func refresh() async {
        guard !inFlight else { return }
        inFlight = true
        var next = latest
        do {
            next.items = try await fetchItems()
            next.runners = try await fetchRunners()
            next.runs = await fetchRuns(next.items, next.runners)
            next.error = nil
            next.updated = Date()
            if latest.updated != nil { notifyChanges(from: latest, to: next) }
        } catch {
            next.error = (error as? Fail)?.message ?? error.localizedDescription
        }
        latest = next
        inFlight = false
        refreshing = false
        updateTitle()
        if popover.isShown { shown = latest }
    }

    func notifyChanges(from old: Snapshot, to new: Snapshot) {
        guard UserDefaults.standard.bool(forKey: "notify") else { return }
        let muted = stored("muted"), kinds = stored("kinds")
        // The label list is its own switch: empty means off.
        func send(_ a: Alert, _ repo: String, _ title: String, _ body: String, _ url: String) {
            let alerts = setting("alerts", repo).split(separator: ",")
            guard !muted.contains(repo), !muted.contains(owner(repo)) else { return }
            if a == .labeled || alerts.contains(Substring(a.rawValue)) {
                post(title, a.title, body, url, repo: repo)
            } else if alerts.contains(Substring(a.rawValue + ":quiet")) {
                post(title, a.title, body, url, repo: repo, quiet: true)
            }
        }
        // Each search an issue or PR newly matches is a reason: mentioned, assigned, asked to review. Reasons notify whether or not
        // they're shown. GitHub keeps matching mentions:@me after the first mention, so later mentions in the same thread read as updates.
        let before = Dictionary(grouping: old.items, by: \.url)
        for (url, all) in Dictionary(grouping: new.items, by: \.url) {
            let i = all[0], o = before[url]?.first
            guard shows(i.repo) else { continue }
            let watched = setting("watchLabels", i.repo).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let gained = Set(all.map(\.kind)).subtracting(before[url]?.map(\.kind) ?? [])
            var body = i.title
            let a: Alert
            if let l = i.labels.first(where: { watched.contains($0.lowercased()) && !(o?.labels.contains($0) ?? false) }) {
                (a, body) = (.labeled, "\(l) · \(i.title)")
            } else if let k = Kind.allCases.filter(gained.contains).compactMap(\.alert).first {
                a = k
            } else if let o, all.contains(where: { kinds.contains($0.kind.rawValue) }) {
                if o.checks != i.checks, let c = i.checks, c != "PENDING", c != "EXPECTED" {
                    a = c == "SUCCESS" ? .checksPassed : .checksFailed
                } else if o.review != i.review, let r = i.review, r != "REVIEW_REQUIRED" {
                    a = r == "APPROVED" ? .approved : .changesRequested
                } else if o.updated != i.updated {
                    a = .updated
                } else { continue }
            } else { continue }
            send(a, i.repo, "\(i.repo) #\(i.number)", body, url)
        }
        let was = Dictionary(old.runners.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in new.runners where shows(r.repo) {
            guard let o = was[r.id] else { continue }
            if o.online != r.online {
                send(r.online ? .runnerOnline : .runnerOffline, r.repo, r.name, r.repo, "https://github.com/\(r.repo)/settings/actions/runners")
            } else if o.busy != r.busy {
                let job = r.busy ? r.job : o.job
                send(r.busy ? .jobStarted : .jobFinished, r.repo, r.name, job?.name ?? r.repo, job?.url ?? "https://github.com/\(r.repo)/actions")
            }
        }
        // Only runs seen unfinished before count, so the first poll after launch doesn't replay old results.
        let ran = Dictionary(old.runs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in new.runs where r.status == "completed" && shows(r.repo) {
            guard let o = ran[r.id], o.status != "completed" else { continue }
            let failed = ["failure", "timed_out", "startup_failure"].contains(r.conclusion ?? "")
            guard failed || r.conclusion == "success" else { continue }
            send(failed ? .runFailed : .runPassed, r.repo, "\(r.repo) · \(r.workflow)", r.title, r.url)
        }
    }

    // Quiet notifications skip the banner and sound and go straight to Notification Center.
    func post(_ title: String, _ subtitle: String, _ body: String, _ url: String, repo: String = "", quiet: Bool = false) {
        let show = stored("content"), c = UNMutableNotificationContent()
        if show.contains("source") { c.title = title }
        if show.contains("event") { c.subtitle = subtitle }
        if show.contains("details") { c.body = body }
        if show.contains("thread") { c.threadIdentifier = repo }
        c.interruptionLevel = quiet ? .passive : .active
        c.userInfo = ["url": url]
        // Several notifications in one poll get one click: play() does nothing while the sound is still playing.
        if UserDefaults.standard.bool(forKey: "sound"), !quiet { keyClick.play() }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // Without permission a test would silently do nothing, so open the settings where it's granted instead.
    func sendTest() async {
        let c = UNUserNotificationCenter.current()
        if await c.notificationSettings().authorizationStatus == .notDetermined { _ = try? await c.requestAuthorization(options: [.alert, .sound]) }
        if await c.notificationSettings().authorizationStatus == .authorized {
            post("osk/gn", "Test notification", "Notifications are working.", "https://github.com/notifications")
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=local.gitbar")!)
        }
    }

    nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        if let s = r.notification.request.content.userInfo["url"] as? String, let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }

    func updateTitle() {
        let n = visible(latest.items).count
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        item.button?.attributedTitle = NSAttributedString(string: n > 0 ? "\(n)" : "", attributes: [.font: font, .baselineOffset: 0.5])
        item.button?.imagePosition = n > 0 ? .imageLeading : .imageOnly
        item.button?.toolTip = latest.error
    }

    func open(_ url: String) {
        NSWorkspace.shared.open(URL(string: url)!)
        popover.performClose(nil)
    }

    // AppKit focuses the first control when the popover opens, which draws a focus ring on the first tab.
    // Clearing it leaves nothing focused while Tab still moves through the controls.
    func popoverDidShow(_ n: Notification) {
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    // Settings replace the lists inside the popover; menus would close on every click.
    @Published var settingsOpen = false

    func popoverDidClose(_ n: Notification) {
        if let m = outsideClick { NSEvent.removeMonitor(m) }
        outsideClick = nil
        settingsOpen = false
        closeDetail()
    }

    // Live while the detail is on screen: local CPU, memory and log every 2 s, GitHub's steps and annotations every 10 s.
    func openDetail(_ r: Runner) {
        detail = Detail(runner: r)
        (worker, lastCPU, detailTicks) = (nil, nil, 0)
        detailTick()
        detailTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.detailTick() }
        }
    }

    func closeDetail() {
        detailTimer?.invalidate()
        detailTimer = nil
        detail = nil
    }

    func detailTick() {
        guard var d = detail else { return }
        if worker.map({ usage($0.pid) == nil }) ?? true { worker = findWorker(d.runner) }
        if let w = worker {
            let procs = allProcesses()
            var kids: [Int32: [Int32]] = [:]
            for p in procs { kids[p.ppid, default: []].append(p.pid) }
            var stack = [w.pid], time = 0.0, memory = 0.0
            while let p = stack.popLast() {
                if let u = usage(p) { time += u.time; memory += u.footprint }
                stack += kids[p] ?? []
            }
            let now = Date()
            // Children that exit between samples take their CPU time with them, so the difference can dip below zero.
            d.cpu = lastCPU.map { max(0, (time - $0.time) / now.timeIntervalSince($0.at) * 100) }
            lastCPU = (time, now)
            d.memory = memory
            d.log = liveLog(w.root)
            d.local = true
        }
        detail = d
        if detailTicks % 5 == 0 { Task { await fetchDetail() } }
        detailTicks += 1
    }

    // The runner's Runner.Worker process lives in <install folder>/bin*/; its .runner file says which runner that is.
    func findWorker(_ r: Runner) -> (pid: Int32, root: String)? {
        for p in allProcesses() {
            guard let path = processPath(p.pid), path.hasSuffix("/Runner.Worker") else { continue }
            let root = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent().path
            if identities[root] == nil { identities[root] = runnerIdentity(root) }
            if let id = identities[root], id.name == r.name, id.url.hasSuffix("/" + r.repo) { return (p.pid, root) }
        }
        return nil
    }

    func fetchDetail() async {
        guard let d = detail, let job = d.runner.job else { return }
        let repo = d.runner.repo
        let info: JobInfo? = try? await api("repos/\(repo)/actions/jobs/\(job.id)")
        var run = d.run
        if run == nil { run = try? await api("repos/\(repo)/actions/runs/\(job.runID)") }
        let notes: [Annotation]? = try? await api("repos/\(repo)/check-runs/\(job.id)/annotations")
        guard detail?.runner.id == d.runner.id else { return }
        detail?.job = info ?? detail?.job
        detail?.run = run
        detail?.annotations = notes ?? detail?.annotations ?? []
    }

    @objc func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            shown = latest
            popover.show(relativeTo: item.button!.bounds, of: item.button!, preferredEdge: .minY)
            // .transient misses clicks in other apps while osk/gn isn't frontmost, so watch for them directly.
            outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// A toggle over one key of a comma-separated stored set; `on` is whether membership means checked.
func member(_ list: Binding<String>, _ key: String, on: Bool = true) -> Binding<Bool> {
    Binding(
        get: { list.wrappedValue.split(separator: ",").contains(Substring(key)) == on },
        set: { v in
            var s = Set(list.wrappedValue.split(separator: ",").map(String.init))
            if v == on { s.insert(key) } else { s.remove(key) }
            list.wrappedValue = s.sorted().joined(separator: ",")
        })
}

// Segmented pickers on macOS show either a symbol or text, never both, so each segment is drawn as one template image.
func tabImage(_ symbol: String, _ text: String) -> Image {
    let s = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))!
    let t = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)])
    let size = NSSize(width: s.size.width + 4 + ceil(t.size().width), height: max(s.size.height, ceil(t.size().height)))
    let img = NSImage(size: size, flipped: false) { _ in
        s.draw(in: NSRect(x: 0, y: (size.height - s.size.height) / 2, width: s.size.width, height: s.size.height))
        t.draw(at: NSPoint(x: s.size.width + 4, y: (size.height - t.size().height) / 2))
        return true
    }
    img.isTemplate = true
    return Image(nsImage: img)
}

enum Grouping: String, CaseIterable {
    case reason, org, repo, status, review, updated, none

    var title: String {
        switch self {
        case .reason: return "Reason"
        case .org: return "Organization"
        case .repo: return "Repository"
        case .status: return "Status"
        case .review: return "Review"
        case .updated: return "Last updated"
        case .none: return "None"
        }
    }

    // Issues have no checks or reviews, and runners have no reason, review or update time.
    func applies(toTab tab: Int) -> Bool {
        switch self {
        case .status: return tab != 1
        case .review: return tab == 0
        case .reason: return tab < 2
        case .updated: return tab != 2
        default: return true
        }
    }
}

enum Sorting: String, CaseIterable {
    case updated, oldest, number, repo, title

    var title: String {
        switch self {
        case .updated: return "Recently updated"
        case .oldest: return "Least recently updated"
        case .number: return "Newest"
        case .repo: return "Repository"
        case .title: return "Title"
        }
    }

    // Runners have no update time or number; they sort by name or repository. Runs have no number worth sorting by.
    func applies(toTab tab: Int) -> Bool {
        switch tab {
        case 2: return self == .repo || self == .title
        case 3: return self != .number
        default: return true
        }
    }

    func sort(_ runs: [Run]) -> [Run] {
        switch self {
        case .oldest: return runs.sorted { $0.updated < $1.updated }
        case .repo: return runs.sorted { ($0.repo.lowercased(), $1.updated) < ($1.repo.lowercased(), $0.updated) }
        case .title: return runs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        default: return runs.sorted { $0.updated > $1.updated }
        }
    }

    func sort(_ items: [Item]) -> [Item] {
        switch self {
        case .updated: return items.sorted { $0.updated > $1.updated }
        case .oldest: return items.sorted { $0.updated < $1.updated }
        case .number: return items.sorted { ($0.repo, $1.number) < ($1.repo, $0.number) }
        case .repo: return items.sorted { ($0.repo.lowercased(), $1.updated) < ($1.repo.lowercased(), $0.updated) }
        case .title: return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    func sort(_ runners: [Runner]) -> [Runner] {
        self == .repo
            ? runners.sorted { ($0.repo.lowercased(), $0.name.lowercased()) < ($1.repo.lowercased(), $1.name.lowercased()) }
            : runners.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

func owner(_ repo: String) -> String { String(repo.split(separator: "/")[0]) }

// Groups keep their rows' original order; the rank orders the groups, then the title breaks ties.
func grouped<T>(_ rows: [T], _ key: (T) -> (rank: Int, title: String)) -> [(title: String, rows: [T])] {
    var out: [(rank: Int, title: String, rows: [T])] = []
    for r in rows {
        let k = key(r)
        if let i = out.firstIndex(where: { $0.title == k.title }) { out[i].rows.append(r) } else { out.append((k.rank, k.title, [r])) }
    }
    return out.sorted { ($0.rank, $0.title.lowercased()) < ($1.rank, $1.title.lowercased()) }.map { ($0.title, $0.rows) }
}

func itemKey(_ i: Item, _ g: Grouping) -> (rank: Int, title: String) {
    switch g {
    case .reason: return (Kind.allCases.firstIndex(of: i.kind)!, i.kind.title)
    case .org: return (0, owner(i.repo))
    case .repo: return (0, i.repo)
    case .status:
        switch i.checks {
        case "FAILURE", "ERROR": return (0, "Failing")
        case "PENDING", "EXPECTED": return (1, "Running")
        case "SUCCESS": return (2, "Passing")
        default: return (3, "No checks")
        }
    case .review:
        if i.review == "CHANGES_REQUESTED" { return (0, "Changes requested") }
        if i.review == "APPROVED" { return (1, "Approved") }
        return i.draft ? (3, "Draft") : (2, "Awaiting review")
    case .updated:
        let age = -i.updated.timeIntervalSinceNow
        if age < 86400 { return (0, "Today") }
        if age < 7 * 86400 { return (1, "This week") }
        if age < 30 * 86400 { return (2, "This month") }
        return (3, "Older")
    case .none: return (0, "")
    }
}

func runKey(_ r: Run, _ g: Grouping) -> (rank: Int, title: String) {
    switch g {
    case .org: return (0, owner(r.repo))
    case .status:
        if r.status == "in_progress" { return (0, "Running") }
        if r.status != "completed" { return (1, "Queued") }
        switch r.conclusion {
        case "failure", "timed_out", "startup_failure": return (2, "Failed")
        case "success": return (3, "Passed")
        default: return (4, "Cancelled or skipped")
        }
    case .updated:
        let age = -r.updated.timeIntervalSinceNow
        if age < 86400 { return (0, "Today") }
        if age < 7 * 86400 { return (1, "This week") }
        return (2, "Older")
    case .none: return (0, "")
    default: return (0, r.repo)
    }
}

func runnerKey(_ r: Runner, _ g: Grouping) -> (rank: Int, title: String) {
    switch g {
    case .org: return (0, owner(r.repo))
    case .status: return !r.online ? (2, "Offline") : r.busy ? (0, "Busy") : (1, "Idle")
    case .none: return (0, "")
    default: return (0, r.repo)
    }
}

// Liquid Glass controls on macOS 26 and later, the earlier borderless look before.
extension View {
    @ViewBuilder func glassControl(circle: Bool = true) -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass).buttonBorderShape(circle ? .circle : .capsule)
        } else {
            buttonStyle(.borderless)
        }
    }

    @ViewBuilder func glassMenu() -> some View {
        if #available(macOS 26, *) {
            // Menus ignore the glass button style, so the glass is drawn behind a borderless menu at a glass button's size.
            menuStyle(.borderlessButton).frame(width: 24, height: 24).glassEffect(.regular.interactive(), in: .circle)
        } else {
            menuStyle(.borderlessButton)
        }
    }
}

// Lets neighbouring glass controls blend into each other, as macOS 26 toolbars do.
struct GlassGroup<C: View>: View {
    @ViewBuilder var content: C

    var body: some View {
        if #available(macOS 26, *) { GlassEffectContainer(spacing: 8) { content } } else { content }
    }
}

struct Panel: View {
    @ObservedObject var m: GitBar
    @State var tab = 0
    @State var hovered: String?
    @AppStorage("kinds") var kinds = ""
    @AppStorage("hidden") var hidden = ""
    @AppStorage("groupBy") var groupBy = Grouping.reason
    @AppStorage("sortBy") var sortBy = Sorting.updated
    @AppStorage("collapsed") var collapsed = ""
    @AppStorage("order") var order = ""
    @State var dropTarget: String?
    @State var detailTab = 0
    @State var settingsPage = 0
    @State var settingsScope: String?
    @Namespace var tabSpace

    // A grouping that doesn't fit this tab falls back to the tab's natural one.
    var grouping: Grouping { groupBy.applies(toTab: tab) ? groupBy : tab >= 2 ? .repo : .reason }
    var sorting: Sorting { sortBy.applies(toTab: tab) ? sortBy : tab == 2 ? .title : .updated }

    var body: some View {
        let items = visible(m.shown.items)
        let runners = m.shown.runners.filter { shows($0.repo) }
        let runs = m.shown.runs.filter { shows($0.repo) }
        return VStack(alignment: .leading, spacing: 10) {
            if m.settingsOpen {
                HStack(spacing: 8) {
                    Button { if settingsScope == nil { m.settingsOpen = false } else { settingsScope = nil } } label: { Image(systemName: "chevron.left") }
                        .glassControl().help("Back").accessibilityLabel("Back")
                    if let scope = settingsScope {
                        Text(scope).font(.headline).lineLimit(1).truncationMode(.middle)
                    } else {
                        Picker("", selection: $settingsPage) {
                            Text("Show").tag(0)
                            Text("Repositories").tag(1)
                            Text("Notifications").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    Spacer()
                }
                .frame(height: 28)
                SettingsView(m: m, page: settingsPage, scope: $settingsScope,
                             repos: Set(m.shown.items.map(\.repo) + m.shown.runners.map(\.repo) + m.shown.runs.map(\.repo)).sorted())
                    .frame(height: 380)
            } else {
                HStack {
                    tabBar(["\(items.filter(\.kind.pr).count)", "\(items.filter { !$0.kind.pr }.count)",
                            "\(runners.filter(\.busy).count)/\(runners.count)", "\(runs.filter { $0.status != "completed" }.count)"])
                        .help("Pull requests, issues, runners busy of total, and runs in progress")
                    Spacer()
                    Menu {
                        Picker("Group by", selection: $groupBy) {
                            ForEach(Grouping.allCases, id: \.self) { Text($0.title).tag($0).disabled(!$0.applies(toTab: tab)) }
                        }
                        .pickerStyle(.inline)
                        Picker("Sort by", selection: $sortBy) {
                            ForEach(Sorting.allCases, id: \.self) { Text(tab == 2 && $0 == .title ? "Name" : $0.title).tag($0).disabled(!$0.applies(toTab: tab)) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down").frame(width: 16, height: 16)
                    }
                    .glassMenu()
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Group by \(grouping.title.lowercased()), sort by \(tab == 2 && sorting == .title ? "name" : sorting.title.lowercased())")
                    .accessibilityLabel("Group and sort")
                }
                .frame(height: 28)
                Group {
                    if m.shown.updated == nil {
                        placeholder(m.shown.error ?? "Loading…", icon: m.shown.error == nil ? "arrow.triangle.pull" : "exclamationmark.triangle")
                    } else if tab >= 2, let d = m.detail {
                        detailView(d)
                    } else if tab == 2 {
                        runnerList(runners)
                    } else if tab == 3 {
                        runList(runs)
                    } else {
                        itemList(items.filter { $0.kind.pr == (tab == 0) }, empty: tab == 0 ? "No open pull requests" : "No open issues")
                    }
                }
                // Fixed height so switching tabs or loading never resizes the popover.
                .frame(height: 380, alignment: .top)
            }
            GlassGroup {
                HStack(spacing: 8) {
                    Button { m.settingsOpen.toggle() } label: { Image(systemName: m.settingsOpen ? "gearshape.fill" : "gearshape").frame(width: 16, height: 16) }
                        .glassControl()
                        .keyboardShortcut(",")
                        .help("Settings (⌘, or ⌘;)")
                        .accessibilityLabel("Settings")
                    Spacer()
                    // The spinner sits inside the button so the button keeps its size while refreshing.
                    Button { m.refreshing = true; Task { await m.refresh() } } label: {
                        Group {
                            if m.refreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: m.shown.error == nil ? "arrow.clockwise" : "exclamationmark.triangle")
                                    .foregroundStyle(m.shown.error == nil ? Color.primary : Color.orange)
                            }
                        }
                        .frame(width: 16, height: 16)
                    }
                    .glassControl()
                    .disabled(m.refreshing)
                    .help([m.shown.error, m.shown.updated.map { "Refresh · updated \(ago($0)) ago" } ?? "Refresh"].compactMap { $0 }.joined(separator: "\n"))
                    .accessibilityLabel("Refresh")
                    Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q").glassControl(circle: false)
                }
            }
            .onChange(of: kinds) { m.updateTitle() }
            .onChange(of: tab) { m.closeDetail() }
            .onChange(of: m.settingsOpen) { settingsScope = nil }
            .onChange(of: hidden) { m.updateTitle() }
        }
        .padding(12)
        .frame(width: 420)
        // A second shortcut needs a second button; this one is invisible and only there for ⌘;.
        .background { Button("") { m.settingsOpen.toggle() }.keyboardShortcut(";").opacity(0).accessibilityHidden(true) }
    }

    // The segmented picker doesn't take on Liquid Glass, so on macOS 26 the tabs are one glass capsule with a sliding accent pill.
    @ViewBuilder func tabBar(_ counts: [String]) -> some View {
        let icons = ["arrow.triangle.pull", "smallcircle.filled.circle", "server.rack", "play.circle"], names = ["Pull requests", "Issues", "Runners", "Runs"]
        if #available(macOS 26, *) {
            HStack(spacing: 2) {
                ForEach(0..<4) { i in
                    Button { withAnimation(.snappy(duration: 0.25)) { tab = i } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: icons[i])
                            Text(counts[i]).monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .foregroundStyle(tab == i ? Color.white : Color.primary)
                        .background { if tab == i { Capsule().fill(Color.accentColor).matchedGeometryEffect(id: "tab", in: tabSpace) } }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(names[i])
                    .accessibilityValue(counts[i])
                    .accessibilityAddTraits(tab == i ? .isSelected : [])
                }
            }
            .padding(2)
            .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Picker("", selection: $tab) {
                ForEach(0..<4) { i in tabImage(icons[i], counts[i]).tag(i).accessibilityLabel(names[i]) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    func placeholder(_ text: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2)
            Text(text).textSelection(.enabled).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func itemList(_ items: [Item], empty: String) -> some View {
        Group {
            if items.isEmpty {
                placeholder(empty, icon: "checkmark.circle")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let groups = ordered(grouped(sorting.sort(items)) { itemKey($0, grouping) })
                        ForEach(groups, id: \.title) { g in
                            if !g.title.isEmpty { header(g.title, count: g.rows.count, titles: groups.map(\.title)) }
                            if g.title.isEmpty || isOpen(g.title).wrappedValue {
                                ForEach(g.rows) { itemRow($0).transition(.opacity) }
                            }
                        }
                    }
                }
            }
        }
    }

    // Collapsed sections are remembered per tab and grouping, so "Draft" under Review stays shut without hiding anything elsewhere.
    func isOpen(_ title: String) -> Binding<Bool> { member($collapsed, "\(tab)|\(grouping.rawValue)|\(title)", on: false) }

    // A section order the user dragged is kept per tab and grouping; sections it doesn't name keep their natural place after it.
    func ordered<T>(_ groups: [(title: String, rows: [T])]) -> [(title: String, rows: [T])] {
        let saved = order.split(separator: "\n").map(String.init), prefix = "\(tab)|\(grouping.rawValue)|"
        func rank(_ t: String) -> Int { saved.firstIndex(of: prefix + t) ?? Int.max }
        return groups.enumerated().sorted { (rank($0.element.title), $0.offset) < (rank($1.element.title), $1.offset) }.map(\.element)
    }

    // Moving down lands after the target, moving up lands before it, like dragging in Finder.
    func move(_ title: String, to target: String, in titles: [String]) {
        guard let from = titles.firstIndex(of: title), let to = titles.firstIndex(of: target), from != to else { return }
        var t = titles
        t.remove(at: from)
        t.insert(title, at: to)
        let prefix = "\(tab)|\(grouping.rawValue)|"
        withAnimation(.easeInOut(duration: 0.2)) {
            order = (order.split(separator: "\n").map(String.init).filter { !$0.hasPrefix(prefix) } + t.map { prefix + $0 }).joined(separator: "\n")
        }
    }

    func header(_ s: String, count: Int, titles: [String]) -> some View {
        let open = isOpen(s)
        let i = titles.firstIndex(of: s)!
        return Button { withAnimation(.easeInOut(duration: 0.2)) { open.wrappedValue.toggle() } } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
                    .frame(width: 10)
                Text(s)
                Text("\(count)").foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(s), \(count)")
        .accessibilityValue(open.wrappedValue ? "Expanded" : "Collapsed")
        .help("Click to collapse, drag to reorder")
        .draggable(s) { Text(s).font(.caption.weight(.semibold)).padding(4) }
        .dropDestination(for: String.self) { dropped, _ in
            guard let d = dropped.first, titles.contains(d) else { return false }
            move(d, to: s, in: titles)
            return true
        } isTargeted: { dropTarget = $0 ? s : (dropTarget == s ? nil : dropTarget) }
        .overlay(alignment: .top) { if dropTarget == s { Capsule().fill(Color.accentColor).frame(height: 2) } }
        .contextMenu {
            Button("Move up") { move(s, to: titles[i - 1], in: titles) }.disabled(i == 0)
            Button("Move down") { move(s, to: titles[i + 1], in: titles) }.disabled(i == titles.count - 1)
            Divider()
            Button("Reset order") {
                let prefix = "\(tab)|\(grouping.rawValue)|"
                withAnimation(.easeInOut(duration: 0.2)) { order = order.split(separator: "\n").filter { !$0.hasPrefix(prefix) }.joined(separator: "\n") }
            }
        }
    }

    func itemRow(_ i: Item) -> some View {
        var meta = "\(i.repo) #\(i.number) · \(ago(i.updated))"
        if i.draft { meta += " · Draft" }
        if i.review == "APPROVED" { meta += " · Approved" }
        if i.review == "CHANGES_REQUESTED" { meta += " · Changes requested" }
        return row(i.id, help: i.title, action: { m.open(i.url) }) {
            stateIcon(i)
            VStack(alignment: .leading, spacing: 2) {
                Text(i.title).lineLimit(1).truncationMode(.tail)
                Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
            }
        }
    }

    func stateIcon(_ i: Item) -> some View {
        let (name, color): (String, Color)
        switch (i.kind.pr, i.checks) {
        case (false, _): (name, color) = ("smallcircle.filled.circle", .green)
        case (_, "SUCCESS"): (name, color) = ("checkmark.circle.fill", .green)
        case (_, "FAILURE"), (_, "ERROR"): (name, color) = ("xmark.circle.fill", .red)
        case (_, "PENDING"), (_, "EXPECTED"): (name, color) = ("clock.fill", .orange)
        default: (name, color) = ("arrow.triangle.pull", .secondary)
        }
        let label = i.kind.pr ? ["SUCCESS": "Checks passed", "FAILURE": "Checks failed", "ERROR": "Checks failed",
                                 "PENDING": "Checks running", "EXPECTED": "Checks running"][i.checks ?? ""] ?? "No checks" : "Open issue"
        return Image(systemName: name).foregroundStyle(color).frame(width: 16).help(label).accessibilityLabel(label)
    }

    func runnerList(_ runners: [Runner]) -> some View {
        Group {
            if runners.isEmpty {
                placeholder("No self-hosted runners in repos you admin", icon: "server.rack")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let groups = ordered(grouped(sorting.sort(runners)) { runnerKey($0, grouping) })
                        ForEach(groups, id: \.title) { g in
                            if !g.title.isEmpty { header(g.title, count: g.rows.count, titles: groups.map(\.title)) }
                            if g.title.isEmpty || isOpen(g.title).wrappedValue {
                                ForEach(g.rows) { runnerRow($0).transition(.opacity) }
                            }
                        }
                    }
                }
            }
        }
    }

    func runList(_ runs: [Run]) -> some View {
        Group {
            if runs.isEmpty {
                placeholder("No recent runs in the repos of your pull requests and runners", icon: "play.circle")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let groups = ordered(grouped(sorting.sort(runs)) { runKey($0, grouping) })
                        ForEach(groups, id: \.title) { g in
                            if !g.title.isEmpty { header(g.title, count: g.rows.count, titles: groups.map(\.title)) }
                            if g.title.isEmpty || isOpen(g.title).wrappedValue {
                                ForEach(g.rows) { runRow($0).transition(.opacity) }
                            }
                        }
                    }
                }
            }
        }
    }

    func runRow(_ r: Run) -> some View {
        let (icon, color, label): (String, Color, String) = switch (r.status, r.conclusion) {
        case ("in_progress", _): ("clock.fill", .orange, "Running")
        case ("completed", "success"): ("checkmark.circle.fill", .green, "Passed")
        case ("completed", "failure"), ("completed", "timed_out"), ("completed", "startup_failure"): ("xmark.circle.fill", .red, "Failed")
        case ("completed", _): ("stop.circle", .secondary, r.conclusion?.capitalized ?? "Done")
        default: ("circle.dashed", .secondary, "Queued")
        }
        var meta = (grouping == .repo ? [] : [r.repo]) + [r.workflow]
        if let b = r.branch { meta.append(b) }
        meta.append(ago(r.updated))
        return row("run\(r.id)", help: "Show run details", action: { Task { await m.openRun(r) } }) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 16).help(label).accessibilityLabel(label)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).lineLimit(1).truncationMode(.tail)
                Text(meta.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
            }
        }
    }

    func runnerRow(_ r: Runner) -> some View {
        let state = !r.online ? "Offline" : r.busy ? "Busy" : "Idle"
        let busy = r.busy && r.job != nil
        return row(r.id, help: busy ? "Show run details" : state,
                   action: { busy ? m.openDetail(r) : m.open("https://github.com/\(r.repo)/settings/actions/runners") }) {
            Circle().fill(r.online ? (r.busy ? Color.orange : Color.green) : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8).frame(width: 16, height: 16)
                .accessibilityLabel(state)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(r.name).lineLimit(1)
                    Spacer()
                    Text(state).foregroundStyle(.secondary)
                }
                Text(((grouping == .repo ? [] : [r.repo]) + r.labels).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let job = r.job {
                    HStack(spacing: 4) {
                        Text(job.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    func detailView(_ d: Detail) -> some View {
        let steps = d.job?.steps ?? []
        let done = steps.filter { $0.status == "completed" }.count
        let errors = d.log.filter { $0.hasPrefix("##[error]") }
        let problems = d.annotations.count + errors.count
        return VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                Button { m.closeDetail() } label: { Image(systemName: "chevron.left") }
                    .glassControl().help("Back to runners").accessibilityLabel("Back")
                Text(d.runner.job?.name ?? d.runner.name).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { m.open(d.job?.html_url ?? d.runner.job?.url ?? "https://github.com/\(d.runner.repo)/actions") } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .glassControl().help("Open on GitHub").accessibilityLabel("Open on GitHub")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(d.run?.display_title ?? " ").lineLimit(1)
                HStack(spacing: 0) {
                    Text(([d.runner.repo, d.job?.head_branch, d.run?.actor?.login, d.runner.name].compactMap { $0 }).joined(separator: " · "))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    if let start = d.job?.started_at {
                        TimelineView(.periodic(from: .now, by: 1)) { c in Text(duration(c.date.timeIntervalSince(start))) }
                            .help("Running for")
                    }
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
                HStack(spacing: 8) {
                ProgressView(value: Double(done), total: Double(max(steps.count, 1)))
                Text("\(done)/\(steps.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .help("Steps finished")
            }
            HStack(spacing: 14) {
                if d.local {
                    Label(d.cpu.map { String(format: "%.0f%%", $0) } ?? "–", systemImage: "cpu").help("CPU, where 100% is one core")
                    Label(d.memory.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "–", systemImage: "memorychip")
                        .help("Memory")
                } else {
                    Text("CPU, memory and live log are measured only for runners on this Mac")
                }
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Picker("", selection: $detailTab) {
                Text("Steps").tag(0)
                Text("Log").tag(1)
                Text(problems > 0 ? "Errors \(problems)" : "Errors").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Group {
                switch detailTab {
                case 0: stepList(steps)
                case 1: logView(d)
                default: errorList(d.annotations, errors)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    func stepList(_ steps: [JobInfo.Step]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(steps, id: \.number) { s in
                    HStack(spacing: 8) {
                        stepIcon(s).frame(width: 16)
                        Text(s.name).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(s.status == "completed" || s.status == "in_progress" ? .primary : .secondary)
                        Spacer(minLength: 8)
                        Group {
                            if let a = s.started_at, let b = s.completed_at {
                                Text(duration(b.timeIntervalSince(a)))
                            } else if let a = s.started_at {
                                TimelineView(.periodic(from: .now, by: 1)) { c in Text(duration(c.date.timeIntervalSince(a))) }
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.vertical, 4).padding(.horizontal, 6)
                }
            }
        }
    }

    func stepIcon(_ s: JobInfo.Step) -> some View {
        Group {
            if s.status == "in_progress" {
                ProgressView().controlSize(.mini)
            } else {
                let (name, color, label): (String, Color, String) = switch (s.status, s.conclusion) {
                case (_, "success"): ("checkmark.circle.fill", .green, "Passed")
                case (_, "failure"): ("xmark.circle.fill", .red, "Failed")
                case (_, "cancelled"): ("stop.circle", .secondary, "Cancelled")
                case (_, "skipped"): ("minus.circle", .secondary, "Skipped")
                default: ("circle.dashed", .secondary, "Waiting")
                }
                Image(systemName: name).foregroundStyle(color).accessibilityLabel(label)
            }
        }
    }

    func logView(_ d: Detail) -> some View {
        Group {
            if !d.local {
                placeholder(d.job?.status == "completed" ? "The full log is on GitHub" : "The live log is shown only for jobs running on this Mac",
                            icon: "doc.text")
            } else if d.log.isEmpty {
                placeholder("No output yet", icon: "doc.text")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(d.log.enumerated()), id: \.offset) { _, line in logLine(line) }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(6)
                    }
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                    .onChange(of: d.log) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
    }

    func logLine(_ line: String) -> some View {
        let (text, color): (String, Color) =
            line.hasPrefix("##[error]") ? (String(line.dropFirst(9)), .red) :
            line.hasPrefix("##[warning]") ? (String(line.dropFirst(11)), .orange) : (line, .primary)
        return Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(color).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func errorList(_ notes: [Annotation], _ lines: [String]) -> some View {
        Group {
            if notes.isEmpty && lines.isEmpty {
                placeholder("No errors so far", icon: "checkmark.circle")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, a in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: a.annotation_level == "failure" ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(a.annotation_level == "failure" ? Color.red : Color.orange)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.title ?? a.message).lineLimit(3)
                                    if a.title != nil { Text(a.message).font(.caption).lineLimit(4) }
                                    Text("\(a.path):\(a.start_line)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                .textSelection(.enabled)
                            }
                        }
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in logLine(l) }
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
    }

    func row<C: View>(_ id: String, help: String, action: @escaping () -> Void, @ViewBuilder content: () -> C) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) { content() }
                .padding(.vertical, 5).padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 5).fill(hovered == id ? Color.primary.opacity(0.08) : .clear))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
    }
}

struct SettingsView: View {
    let m: GitBar
    let page: Int
    @Binding var scope: String?
    let repos: [String]
    @AppStorage("kinds") var kinds = ""
    @AppStorage("hidden") var hidden = ""
    @AppStorage("muted") var muted = ""
    @AppStorage("notify") var notify = true
    @AppStorage("sound") var sound = false
    @AppStorage("content") var content = ""

    var body: some View {
        Group {
            if let scope {
                Form { NotifyRules(scope: scope) }.formStyle(.grouped).id(scope)
            } else {
                switch page {
                case 0: Form {
                    Section("Pull requests") {
                        ForEach(Kind.allCases.filter(\.pr), id: \.self) { Toggle($0.title, isOn: member($kinds, $0.rawValue)) }
                    }
                    Section("Issues") {
                        ForEach(Kind.allCases.filter { !$0.pr }, id: \.self) { Toggle($0.title, isOn: member($kinds, $0.rawValue)) }
                    }
                }
                .formStyle(.grouped)
                case 1: repositories
                default: Form {
                    Section {
                        Toggle("Notifications", isOn: $notify)
                        Toggle("Play sound", isOn: $sound).disabled(!notify)
                        Button("Send test notification") { Task { await m.sendTest() } }
                    }
                    Section {
                        Toggle("Source", isOn: member($content, "source")).help("Repository and number, runner, or workflow")
                        Toggle("Event", isOn: member($content, "event")).help("What happened, such as Checks failed")
                        Toggle("Details", isOn: member($content, "details")).help("Pull request, issue or run title, or job name")
                        Toggle("Group by repository", isOn: member($content, "thread")).help("Stacks each repository's notifications in Notification Center")
                        // Banners versus alerts that stay until dismissed is a per-app choice macOS keeps for itself.
                        Button("Banner or alert style…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=local.gitbar")!)
                        }
                    } header: {
                        Text("Contents")
                    }
                    .disabled(!notify)
                    NotifyRules(scope: nil)
                }
                .formStyle(.grouped)
                .onChange(of: notify) { if notify { m.askToNotify() } }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // Two switches per organization and repository: whether it shows in GitBar, and whether it may notify.
    var repositories: some View {
        let owners = Dictionary(grouping: repos) { owner($0) }
        return Form {
            ForEach(owners.keys.sorted { $0.lowercased() < $1.lowercased() }, id: \.self) { o in
                Section {
                    repoRow("All of \(o)", o, bold: true)
                    ForEach(owners[o]!, id: \.self) { r in
                        repoRow(String(r.dropFirst(o.count + 1)), r, bold: false)
                            .disabled(hidden.split(separator: ",").contains(Substring(o)))
                    }
                } header: {
                    HStack {
                        Text(o)
                        Spacer()
                        Text("Show").frame(width: 50)
                        Text("Notify").frame(width: 50)
                        Color.clear.frame(width: 20)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    func repoRow(_ name: String, _ key: String, bold: Bool) -> some View {
        HStack {
            Text(name).fontWeight(bold ? .medium : .regular).lineLimit(1).truncationMode(.middle).help(key)
            Spacer()
            Toggle("Show \(key)", isOn: member($hidden, key, on: false)).labelsHidden().frame(width: 50)
            Toggle("Notify for \(key)", isOn: member($muted, key, on: false)).labelsHidden().frame(width: 50)
                .disabled(!notify || hidden.split(separator: ",").contains(Substring(key)))
            let custom = UserDefaults.standard.string(forKey: "alerts.\(key)") != nil
            Button { scope = key } label: { Image(systemName: custom ? "bell.badge.fill" : "chevron.right") }
                .buttonStyle(.borderless)
                .foregroundStyle(custom ? Color.accentColor : Color.secondary)
                .frame(width: 20)
                .help(custom ? "\(key) has its own notification settings" : "Notification settings for \(key)")
                .accessibilityLabel("Notification settings for \(key)")
                .disabled(!notify)
        }
        .toggleStyle(.checkbox)
    }
}

// Which events notify, globally (scope nil) or for one organization or repository.
// A scope's keys exist only while it overrides; removing them falls back to the organization, then the global settings.
struct NotifyRules: View {
    let scope: String?
    @AppStorage var alerts: String?
    @AppStorage var watchLabels: String?
    @AppStorage("notify") var notify = true

    init(scope: String?) {
        self.scope = scope
        _alerts = AppStorage(scope.map { "alerts.\($0)" } ?? "alerts")
        _watchLabels = AppStorage(scope.map { "watchLabels.\($0)" } ?? "watchLabels")
    }

    var body: some View {
        if let scope {
            let parent = scope.contains("/") && UserDefaults.standard.string(forKey: "alerts.\(owner(scope))") != nil ? owner(scope) : "global settings"
            Section {
                Toggle("Same as \(parent)", isOn: Binding(
                    get: { alerts == nil },
                    set: { same in
                        // Overriding starts from what applies now, so nothing changes until a switch is flipped.
                        (alerts, watchLabels) = same ? (nil, nil) : (setting("alerts", scope), setting("watchLabels", scope))
                    }))
            }
        }
        Group {
            Section("Why it's on your list") { toggles([.reviewRequested, .mentioned, .assigned]) }
            Section {
                TextField("Watched labels", text: Binding(get: { watchLabels ?? setting("watchLabels", scope!) }, set: { watchLabels = $0 }), prompt: Text("bug, urgent"))
            } footer: {
                Text("Notifies when one of these labels is added to a pull request or issue on your list.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Changes") { toggles([.checksFailed, .checksPassed, .approved, .changesRequested, .updated]) }
            Section("Runners") { toggles([.runnerOffline, .runnerOnline, .jobStarted, .jobFinished]) }
            Section("Runs") { toggles([.runFailed, .runPassed]) }
        }
        .disabled(!notify || alerts == nil)
    }

    func toggles(_ list: [Alert]) -> some View {
        let shown = Binding(get: { alerts ?? setting("alerts", scope!) }, set: { alerts = $0 })
        return ForEach(list, id: \.self) { a in
            Picker(a.title, selection: Binding(
                get: { member(shown, a.rawValue).wrappedValue ? 2 : member(shown, a.rawValue + ":quiet").wrappedValue ? 1 : 0 },
                set: { v in
                    member(shown, a.rawValue).wrappedValue = v == 2
                    member(shown, a.rawValue + ":quiet").wrappedValue = v == 1
                })) {
                Text("Off").tag(0)
                Text("Notification Center only").tag(1)
                Text("Banner").tag(2)
            }
        }
    }
}

// build.sh runs `gn --icon file.png` to draw the app icon from the same mark: black on a white macOS icon tile.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--icon" {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185).fill()
    githubMark.draw(in: NSRect(x: 232, y: 232, width: 560, height: 560))
    NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = GitBar()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
