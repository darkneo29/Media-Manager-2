import Foundation

extension UnraidService {
    @discardableResult func startVm(id: String) async throws -> UnraidVMCommandResult { try await performVmAction("start", id: id) }
    @discardableResult func stopVm(id: String) async throws -> UnraidVMCommandResult { try await performVmAction("stop", id: id) }
    @discardableResult func forceStopVm(id: String) async throws -> UnraidVMCommandResult { try await performVmAction("forceStop", id: id) }
    @discardableResult func restartVm(id: String) async throws -> UnraidVMCommandResult { try await performVmAction("reboot", id: id) }
    @discardableResult func pauseVm(id: String) async throws -> UnraidVMCommandResult { try await performVmAction("pause", id: id) }
    @discardableResult func resumeVm(id: String) async throws -> UnraidVMCommandResult { try await performVmAction("resume", id: id) }

    private struct VmActionResponse: Codable {
        let vm: Result
        struct Result: Codable { let result: Bool }
    }

    private final class RebootObservation {
        var verification = UnraidVMVerification(action: "reboot")
        var completed = false
        var lastState: VmState?
        var error: String?
        var terminalError = false
        func observe(_ state: VmState) {
            lastState = state
            completed = verification.observe(state) || completed
            error = nil
        }
    }

    func invalidateDockerState() async {
        await readCache.invalidate(keys: ["containers", "containerSummary"])
    }

    private func performVmAction(_ action: String, id: String) async throws -> UnraidVMCommandResult {
        let context = try requestContext()
        if let caps = capabilityState, caps.connection == context {
            let access = caps.value.vmAction(action)
            guard access.permitsAttempt else { throw UnraidError.featureUnavailable(access.explanation ?? "Command unavailable") }
        }
        let key = CommandKey(url: context.url, resource: "vm:\(id)")
        guard activeCommands.insert(key).inserted else { throw UnraidError.commandInProgress }
        defer { activeCommands.remove(key) }
        await readCache.invalidate(keys: ["vms"])

        // Observe during reboot as well as afterward: some API versions wait for
        // shutdown/start inside the mutation, and otherwise that transition is missed.
        let observation = RebootObservation()
        let observer: Task<Void, Never>? = action == "reboot" ? Task {
            while !Task.isCancelled {
                do { observation.observe(try await self.currentVMState(id: id, context: context)) }
                catch {
                    observation.error = error.localizedDescription
                    observation.terminalError = !Self.shouldRetryVMVerification(error)
                    if observation.terminalError { return }
                }
                do { try await Task.sleep(for: .seconds(max(0.001, self.verificationInterval))) }
                catch { return }
            }
        } : nil
        defer { observer?.cancel() }

        do {
            let response: GraphQLResponse<VmActionResponse> = try await executeQuery(
                "mutation VMCommand($id: PrefixedID!) { vm { result: \(action)(id: $id) } }",
                variables: ["id": id], timeout: 120, context: context)
            guard let accepted = response.data?.vm.result else { throw UnraidError.noData }
            guard accepted else { throw UnraidError.graphQLError("VM command was not successful") }
            var verifier = UnraidVMVerification(action: action)
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(max(0.01, Double(verificationAttempts) * verificationInterval)))
            var lastError: String?
            for _ in 0..<max(1, verificationAttempts) {
                try Task.checkCancellation()
                if action == "reboot" {
                    if observation.completed {
                        await readCache.invalidate(keys: ["vms"])
                        return .verified
                    }
                    lastError = observation.error
                    if observation.terminalError { break }
                } else {
                    do {
                        if verifier.observe(try await currentVMState(id: id, context: context)) {
                            await readCache.invalidate(keys: ["vms"])
                            return .verified
                        }
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        lastError = error.localizedDescription
                        if !Self.shouldRetryVMVerification(error) { break }
                    }
                }
                if clock.now >= deadline { break }
                try await Task.sleep(for: .seconds(max(0.001, verificationInterval)))
            }
            await readCache.invalidate(keys: ["vms"])
            if let lastError { return .unverified("Command accepted, but the VM state could not be verified: \(lastError)") }
            if action == "reboot" {
                return .unverified("Reboot accepted, but a shutdown-to-running transition was not observed. Check the VM before issuing another command.")
            }
            return .unverified("Command accepted, but the expected VM state was not observed before verification timed out. The operation may still be in progress.")
        } catch {
            await readCache.invalidate(keys: ["vms"])
            throw error
        }
    }

    private static func shouldRetryVMVerification(_ error: Error) -> Bool {
        // Stop bounded verification on throttling; the shared cache preserves
        // Retry-After for the status refresh that follows this command.
        if case UnraidError.rateLimited = error { return false }
        return shouldRetryRead(error)
    }

    func currentVMState(id: String, context: UnraidConnection) async throws -> VmState {
        // Bypass cached status while checking command completion.
        let response: GraphQLResponse<VMsResponse> = try await executeQuery("query VerifyVM { \(Self.vmFields) }", timeout: 5, context: context)
        guard let vm = response.data?.vms.domains?.first(where: { $0.id == id || $0.uuid == id }) else {
            throw UnraidError.featureUnavailable("The VM is no longer present in the server's domain list.")
        }
        return VmState(rawValue: vm.state.uppercased()) ?? .unknown
    }
}
