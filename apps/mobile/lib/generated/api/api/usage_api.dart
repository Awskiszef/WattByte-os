//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class UsageApi {
  UsageApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Daily totals across all devices in [from, to]
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] from (required):
  ///
  /// * [String] to (required):
  Future<Response> apiV1UsageDailyGetWithHttpInfo(
    String from,
    String to, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/usage/daily';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    queryParams.addAll(_queryParams('', 'from', from));
    queryParams.addAll(_queryParams('', 'to', to));

    const contentTypes = <String>[];

    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Daily totals across all devices in [from, to]
  ///
  /// Parameters:
  ///
  /// * [String] from (required):
  ///
  /// * [String] to (required):
  Future<UsageDailyResponse?> apiV1UsageDailyGet(
    String from,
    String to, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1UsageDailyGetWithHttpInfo(
      from,
      to,
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
        'UsageDailyResponse',
      ) as UsageDailyResponse;
    }
    return null;
  }

  /// Upload per-day aggregates for one installation; safe to repeat
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [UsageSyncRequest] usageSyncRequest (required):
  Future<Response> apiV1UsageSyncPostWithHttpInfo(
    UsageSyncRequest usageSyncRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/usage/sync';

    // ignore: prefer_final_locals
    Object? postBody = usageSyncRequest;

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

  /// Upload per-day aggregates for one installation; safe to repeat
  ///
  /// Parameters:
  ///
  /// * [UsageSyncRequest] usageSyncRequest (required):
  Future<UsageSyncResponse?> apiV1UsageSyncPost(
    UsageSyncRequest usageSyncRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1UsageSyncPostWithHttpInfo(
      usageSyncRequest,
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
        'UsageSyncResponse',
      ) as UsageSyncResponse;
    }
    return null;
  }
}
