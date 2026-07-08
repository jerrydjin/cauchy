import FoundationModels
func test(_ channel: LanguageModelExecutorGenerationChannel) async throws {
    await channel.send(.response(entryID: "123", action: .appendText("hi", segmentID: nil, tokenCount: 0)))
}
