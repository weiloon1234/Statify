import Foundation
import SystemConfiguration
import CoreWLAN

struct NetworkInfo {
    var wifiName: String?
    var localIP: String?
    var routerIP: String?
    var publicIP: String?
    var countryCode: String?
    var countryName: String?
    var countryFlag: String?
}

final class NetworkInfoService {
    private var cachedPublicInfo: NetworkInfo?
    private var lastPublicInfoFetch: Date?
    private let publicInfoTTL: TimeInterval = 300 // 5 minutes

    func getLocalInfo() -> NetworkInfo {
        var info = NetworkInfo()
        info.wifiName = getWiFiName()
        info.localIP = getLocalIP()
        info.routerIP = getRouterIP()
        return info
    }

    func getPublicInfo(completion: @escaping (NetworkInfo) -> Void) {
        // Return cached result if within TTL
        if let cached = cachedPublicInfo,
           let lastFetch = lastPublicInfoFetch,
           Date().timeIntervalSince(lastFetch) < publicInfoTTL {
            completion(cached)
            return
        }

        let group = DispatchGroup()
        var publicIP: String?
        var countryCode: String?
        var countryName: String?
        var countryFlag: String?

        group.enter()
        fetchPublicIP { ip in
            publicIP = ip
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            if let ip = publicIP {
                group.enter()
                self?.fetchCountryInfo(ip: ip) { code, name, flag in
                    countryCode = code
                    countryName = name
                    countryFlag = flag
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                var info = NetworkInfo()
                info.publicIP = publicIP
                info.countryCode = countryCode
                info.countryName = countryName
                info.countryFlag = countryFlag
                self?.cachedPublicInfo = info
                self?.lastPublicInfoFetch = Date()
                completion(info)
            }
        }
    }

    private func getWiFiName() -> String? {
        let client = CWWiFiClient.shared()
        return client.interface()?.ssid()
    }

    private func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            let interface = ptr!.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
            ptr = ptr!.pointee.ifa_next
        }
        return address
    }

    private func getRouterIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            let interface = ptr!.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_dstaddr, socklen_t(interface.ifa_dstaddr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    let dst = String(cString: hostname)
                    if dst != "0.0.0.0" && !dst.isEmpty {
                        address = dst
                    }
                }
            }
            ptr = ptr!.pointee.ifa_next
        }
        return address
    }

    private func fetchPublicIP(completion: @escaping (String?) -> Void) {
        fetchIP(from: "https://api.ipify.org?format=json", key: "ip") { ip in
            if let ip = ip {
                completion(ip)
            } else {
                self.fetchIP(from: "https://api.seeip.org/jsonip", key: "ip") { fallback in
                    completion(fallback)
                }
            }
        }
    }

    private func fetchIP(from urlString: String, key: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: urlString) else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let ip = json[key] else {
                completion(nil); return
            }
            completion(ip)
        }.resume()
    }

    private func fetchCountryInfo(ip: String, completion: @escaping (String?, String?, String?) -> Void) {
        fetchCountry(from: "https://country.is/\(ip)") { code, name, flag in
            if let code = code {
                completion(code, name, flag)
            } else {
                self.fetchCountry(from: "https://ipapi.co/\(ip)/json/") { code2, name2, flag2 in
                    completion(code2, name2, flag2)
                }
            }
        }
    }

    private func fetchCountry(from urlString: String, completion: @escaping (String?, String?, String?) -> Void) {
        guard let url = URL(string: urlString) else { completion(nil, nil, nil); return }
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data else {
                completion(nil, nil, nil); return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil, nil, nil); return
            }
            let code = json["country"] as? String ?? json["country_code"] as? String
            let name = json["name"] as? String ?? json["country_name"] as? String ?? code
            guard let code = code else { completion(nil, nil, nil); return }
            let flag = self.codeToFlag(code: code)
            completion(code, name, flag)
        }.resume()
    }

    private func codeToFlag(code: String) -> String {
        let base: UInt32 = 127397
        var scalarString = ""
        for unicode in code.uppercased().unicodeScalars {
            scalarString.unicodeScalars.append(UnicodeScalar(base + unicode.value)!)
        }
        return scalarString
    }
}
