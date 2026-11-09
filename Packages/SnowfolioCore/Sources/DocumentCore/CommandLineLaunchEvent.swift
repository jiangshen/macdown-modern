import Carbon
import Foundation

/// Public LaunchServices first-event delivery supports both a warm and cold app.
/// Keep private document contents out of URL strings, defaults and temporary files.
public enum CommandLineLaunchEvent {
  public static let eventClass: AEEventClass = 0x534E_464C  // SNFL
  public static let eventID: AEEventID = 0x436C_696F  // Clio

  public static func encode(_ request: CommandLineLaunchRequest) throws -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(
      eventClass: eventClass, eventID: eventID, targetDescriptor: nil,
      returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
    )
    guard
      let payload = NSAppleEventDescriptor(
        descriptorType: typeData, data: try JSONEncoder().encode(request))
    else { throw CocoaError(.coderInvalidValue) }
    event.setParam(payload, forKeyword: AEKeyword(keyDirectObject))
    return event
  }

  public static func payload(from event: NSAppleEventDescriptor) throws -> Data {
    guard event.eventClass == eventClass, event.eventID == eventID,
      let payload = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)),
      payload.descriptorType == typeData
    else { throw CommandLineInvocationError.unsupportedMessage }
    return payload.data
  }

  public static func decode(_ event: NSAppleEventDescriptor) throws -> CommandLineLaunchRequest {
    try JSONDecoder().decode(CommandLineLaunchRequest.self, from: payload(from: event))
  }

  @concurrent public static func decodePayload(_ data: Data) async throws
    -> CommandLineLaunchRequest
  {
    try Task.checkCancellation()
    let request = try JSONDecoder().decode(CommandLineLaunchRequest.self, from: data)
    try Task.checkCancellation()
    return request
  }
}
