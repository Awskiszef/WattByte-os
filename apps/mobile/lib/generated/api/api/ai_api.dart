//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class AiApi {
  AiApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// One observation about a period
  ///
  /// Input must be pre-computed aggregates only; the model never calculates.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [AIGenerateRequest] aIGenerateRequest (required):
  Future<Response> apiV1AiInsightPostWithHttpInfo(
    AIGenerateRequest aIGenerateRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/ai/insight';

    // ignore: prefer_final_locals
    Object? postBody = aIGenerateRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];

    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// One observation about a period
  ///
  /// Input must be pre-computed aggregates only; the model never calculates.
  ///
  /// Parameters:
  ///
  /// * [AIGenerateRequest] aIGenerateRequest (required):
  Future<AIGenerateResponse?> apiV1AiInsightPost(
    AIGenerateRequest aIGenerateRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1AiInsightPostWithHttpInfo(
      aIGenerateRequest,
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty &&
        response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(
        await _decodeBodyBytes(response),
        'AIGenerateResponse',
      ) as AIGenerateResponse;
    }
    return null;
  }

  /// Summary of a month
  ///
  /// Input must be pre-computed aggregates only; the model never calculates.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [AIGenerateRequest] aIGenerateRequest (required):
  Future<Response> apiV1AiMonthlySummaryPostWithHttpInfo(
    AIGenerateRequest aIGenerateRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/ai/monthly-summary';

    // ignore: prefer_final_locals
    Object? postBody = aIGenerateRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];

    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Summary of a month
  ///
  /// Input must be pre-computed aggregates only; the model never calculates.
  ///
  /// Parameters:
  ///
  /// * [AIGenerateRequest] aIGenerateRequest (required):
  Future<AIGenerateResponse?> apiV1AiMonthlySummaryPost(
    AIGenerateRequest aIGenerateRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1AiMonthlySummaryPostWithHttpInfo(
      aIGenerateRequest,
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty &&
        response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(
        await _decodeBodyBytes(response),
        'AIGenerateResponse',
      ) as AIGenerateResponse;
    }
    return null;
  }

  /// Playful roast (tone is always roast)
  ///
  /// Input must be pre-computed aggregates only; the model never calculates.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [AIGenerateRequest] aIGenerateRequest (required):
  Future<Response> apiV1AiRoastPostWithHttpInfo(
    AIGenerateRequest aIGenerateRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/ai/roast';

    // ignore: prefer_final_locals
    Object? postBody = aIGenerateRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];

    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Playful roast (tone is always roast)
  ///
  /// Input must be pre-computed aggregates only; the model never calculates.
  ///
  /// Parameters:
  ///
  /// * [AIGenerateRequest] aIGenerateRequest (required):
  Future<AIGenerateResponse?> apiV1AiRoastPost(
    AIGenerateRequest aIGenerateRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1AiRoastPostWithHttpInfo(
      aIGenerateRequest,
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty &&
        response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(
        await _decodeBodyBytes(response),
        'AIGenerateResponse',
      ) as AIGenerateResponse;
    }
    return null;
  }

  /// Summary of a week
  ///
  /// Input must be pre-computed aggregates only; the model never calculates.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [AIGenerateRequest] aIGenerateRequest (required):
  Future<Response> apiV1AiWeeklySummaryPostWithHttpInfo(
    AIGenerateRequest aIGenerateRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/ai/weekly-summary';

    // ignore: prefer_final_locals
    Object? postBody = aIGenerateRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];

    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Summary of a week
  ///
  /// Input must be pre-computed aggregates only; the model never calculates.
  ///
  /// Parameters:
  ///
  /// * [AIGenerateRequest] aIGenerateRequest (required):
  Future<AIGenerateResponse?> apiV1AiWeeklySummaryPost(
    AIGenerateRequest aIGenerateRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1AiWeeklySummaryPostWithHttpInfo(
      aIGenerateRequest,
      abortTrigger: abortTrigger,
    );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty &&
        response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(
        await _decodeBodyBytes(response),
        'AIGenerateResponse',
      ) as AIGenerateResponse;
    }
    return null;
  }
}
