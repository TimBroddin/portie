//
//  Port.swift
//  Portie
//
//  Created by Tim Broddin on 05/02/2026.
//

import Foundation
import Observation

struct Port: Codable, Identifiable, Equatable {
    var id: Int { port }
    let port: Int
    var label: String?

    init(port: Int, label: String? = nil) {
        self.port = port
        self.label = label
    }
}

@MainActor
@Observable
final class PortStorage {
    static let shared = PortStorage()

    private let key = "monitoredPorts"

    var ports: [Port] {
        didSet {
            save()
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Port].self, from: data) {
            self.ports = decoded
        } else {
            self.ports = []
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(ports) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    func addPort(_ port: Int, label: String? = nil) {
        guard !ports.contains(where: { $0.port == port }) else { return }
        ports.append(Port(port: port, label: label))
    }

    func removePort(_ port: Int) {
        ports.removeAll { $0.port == port }
    }

    func updateLabel(for port: Int, label: String?) {
        if let index = ports.firstIndex(where: { $0.port == port }) {
            ports[index].label = label
        }
    }
}
