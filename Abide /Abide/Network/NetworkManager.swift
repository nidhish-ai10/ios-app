//
//  NetworkManager.swift
//  TEST
//
//  Created by Bairineni Nidhish rao on 6/16/25.
//

import Foundation

// MARK: - Network Error Types
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case noData
    case invalidResponse
    case requestFailed(Error)
    case decodingError(Error)
    case encodingError(Error)
    case serverError(Int, Data?)
    case unauthorized
    case forbidden
    case notFound
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .invalidResponse:
            return "Invalid response"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .serverError(let code, _):
            return "Server error with status code: \(code)"
        case .unauthorized:
            return "Unauthorized access"
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .timeout:
            return "Request timeout"
        }
    }
}

// MARK: - HTTP Method
enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
    case PATCH = "PATCH"
}

// MARK: - Network Request Protocol
protocol NetworkRequest {
    var url: URL { get }
    var method: HTTPMethod { get }
    var headers: [String: String]? { get }
    var body: Data? { get }
    var timeoutInterval: TimeInterval { get }
}

// MARK: - Default Network Request Implementation
struct APIRequest: NetworkRequest {
    let url: URL
    let method: HTTPMethod
    let headers: [String: String]?
    let body: Data?
    let timeoutInterval: TimeInterval
    
    init(url: URL, method: HTTPMethod = .GET, headers: [String: String]? = nil, body: Data? = nil, timeoutInterval: TimeInterval = 30.0) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeoutInterval = timeoutInterval
    }
}

// MARK: - Network Response
struct NetworkResponse {
    let data: Data
    let response: URLResponse
    let statusCode: Int
    
    init(data: Data, response: URLResponse) throws {
        self.data = data
        self.response = response
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        self.statusCode = httpResponse.statusCode
    }
}

// MARK: - Network Manager
actor NetworkManager {
    static let shared = NetworkManager()
    
    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
        
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
    }
    
    // MARK: - Generic Network Methods
    
    /// Perform a network request and return raw response
    func performRequest(_ request: NetworkRequest) async throws -> NetworkResponse {
        let urlRequest = try createURLRequest(from: request)
        
        do {
            let (data, response) = try await session.data(for: urlRequest)
            let networkResponse = try NetworkResponse(data: data, response: response)
            
            // Check for HTTP errors
            try validateResponse(networkResponse)
            
            return networkResponse
        } catch {
            if error is NetworkError {
                throw error
            } else {
                throw NetworkError.requestFailed(error)
            }
        }
    }
    
    /// Perform request with JSON encoding for request body and JSON decoding for response
    func performJSONRequest<T: Codable, R: Codable>(
        _ request: NetworkRequest,
        requestBody: T? = nil,
        responseType: R.Type
    ) async throws -> R {
        
        var modifiedRequest = request
        
        // Encode request body if provided
        if let requestBody = requestBody {
            do {
                let bodyData = try jsonEncoder.encode(requestBody)
                modifiedRequest = APIRequest(
                    url: request.url,
                    method: request.method,
                    headers: addContentTypeHeader(to: request.headers),
                    body: bodyData,
                    timeoutInterval: request.timeoutInterval
                )
            } catch {
                throw NetworkError.encodingError(error)
            }
        }
        
        let response = try await performRequest(modifiedRequest)
        
        // Decode response
        do {
            let decodedResponse = try jsonDecoder.decode(R.self, from: response.data)
            return decodedResponse
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
    
    /// Perform request with custom request body and JSON response
    func performRequestWithJSONResponse<R: Codable>(
        _ request: NetworkRequest,
        responseType: R.Type
    ) async throws -> R {
        
        let response = try await performRequest(request)
        
        do {
            let decodedResponse = try jsonDecoder.decode(R.self, from: response.data)
            return decodedResponse
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
    
    /// Perform request and return raw data
    func performDataRequest(_ request: NetworkRequest) async throws -> Data {
        let response = try await performRequest(request)
        return response.data
    }
    
    // MARK: - Helper Methods
    
    private func createURLRequest(from request: NetworkRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = request.timeoutInterval
        
        // Add headers
        if let headers = request.headers {
            for (key, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Add body
        urlRequest.httpBody = request.body
        
        return urlRequest
    }
    
    private func validateResponse(_ response: NetworkResponse) throws {
        switch response.statusCode {
        case 200...299:
            return // Success
        case 400:
            throw NetworkError.invalidResponse
        case 401:
            throw NetworkError.unauthorized
        case 403:
            throw NetworkError.forbidden
        case 404:
            throw NetworkError.notFound
        case 408:
            throw NetworkError.timeout
        case 500...599:
            throw NetworkError.serverError(response.statusCode, response.data)
        default:
            throw NetworkError.serverError(response.statusCode, response.data)
        }
    }
    
    private func addContentTypeHeader(to headers: [String: String]?) -> [String: String] {
        var modifiedHeaders = headers ?? [:]
        if modifiedHeaders["Content-Type"] == nil {
            modifiedHeaders["Content-Type"] = "application/json"
        }
        return modifiedHeaders
    }
}

// MARK: - Convenience Extensions
extension NetworkManager {
    
    /// Quick GET request with JSON response
    func get<R: Codable>(
        url: URL,
        headers: [String: String]? = nil,
        responseType: R.Type
    ) async throws -> R {
        let request = APIRequest(url: url, method: .GET, headers: headers)
        return try await performRequestWithJSONResponse(request, responseType: responseType)
    }
    
    /// Quick POST request with JSON body and response
    func post<T: Codable, R: Codable>(
        url: URL,
        body: T,
        headers: [String: String]? = nil,
        responseType: R.Type
    ) async throws -> R {
        let request = APIRequest(url: url, method: .POST, headers: headers)
        return try await performJSONRequest(request, requestBody: body, responseType: responseType)
    }
    
    /// Quick POST request with custom body data
    func post<R: Codable>(
        url: URL,
        bodyData: Data,
        headers: [String: String]? = nil,
        responseType: R.Type
    ) async throws -> R {
        let request = APIRequest(url: url, method: .POST, headers: headers, body: bodyData)
        return try await performRequestWithJSONResponse(request, responseType: responseType)
    }
}

// MARK: - Logging Extension (Optional)
extension NetworkManager {
    private func logRequest(_ request: URLRequest) {
        #if DEBUG
        print("🌐 Network Request:")
        print("URL: \(request.url?.absoluteString ?? "Unknown")")
        print("Method: \(request.httpMethod ?? "Unknown")")
        if let headers = request.allHTTPHeaderFields {
            print("Headers: \(headers)")
        }
        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            print("Body: \(bodyString)")
        }
        #endif
    }
    
    private func logResponse(_ response: NetworkResponse) {
        #if DEBUG
        print("📱 Network Response:")
        print("Status Code: \(response.statusCode)")
        if let responseString = String(data: response.data, encoding: .utf8) {
            print("Response: \(responseString)")
        }
        #endif
    }
} 