//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class AccountApi {
  AccountApi([ApiClient? apiClient])
      : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Delete the synced cloud data but keep the account
  ///
  /// Removes, in one transaction, the daily usage, charging and monthly summaries, AI generation log and AI quota counters. Keeps the account, its sessions, subscriptions, settings and registered devices, so sync can resume. `?devices=true` also removes the devices. Idempotent: repeating it deletes nothing and answers zeros.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] devices:
  Future<Response> apiV1MeCloudDataDeleteWithHttpInfo({
    String? devices,
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/me/cloud-data';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (devices != null) {
      queryParams.addAll(_queryParams('', 'devices', devices));
    }

    const contentTypes = <String>[];

    return apiClient.invokeAPI(
      path,
      'DELETE',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Delete the synced cloud data but keep the account
  ///
  /// Removes, in one transaction, the daily usage, charging and monthly summaries, AI generation log and AI quota counters. Keeps the account, its sessions, subscriptions, settings and registered devices, so sync can resume. `?devices=true` also removes the devices. Idempotent: repeating it deletes nothing and answers zeros.
  ///
  /// Parameters:
  ///
  /// * [String] devices:
  Future<CloudDataDeleteResponse?> apiV1MeCloudDataDelete({
    String? devices,
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1MeCloudDataDeleteWithHttpInfo(
      devices: devices,
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
        'CloudDataDeleteResponse',
      ) as CloudDataDeleteResponse;
    }
    return null;
  }

  /// Delete the account and every cloud record (GDPR erasure)
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> apiV1MeDeleteWithHttpInfo({
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/me';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];

    return apiClient.invokeAPI(
      path,
      'DELETE',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Delete the account and every cloud record (GDPR erasure)
  Future<String?> apiV1MeDelete({
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1MeDeleteWithHttpInfo(
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
        'String',
      ) as String;
    }
    return null;
  }

  /// Export everything stored about the account
  ///
  /// A JSON document (`schemaVersion`, account, settings, devices with design capacity and estimated full-charge capacity, daily usage, charging and monthly summaries, AI generation metadata, subscriptions), sent as an attachment `wattbyte-export-YYYY-MM-DD.json`. Never contains the password hash, sessions or refresh tokens, or another user's data. `?format=csv` returns only the daily usage as RFC 4180 `text/csv; charset=utf-8`. At most 10000 rows per collection (the newest); a cut collection is flagged in `limits.truncated` (CSV: header `x-wattbyte-truncated`).
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] format:
  Future<Response> apiV1MeExportGetWithHttpInfo({
    String? format,
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/me/export';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (format != null) {
      queryParams.addAll(_queryParams('', 'format', format));
    }

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

  /// Export everything stored about the account
  ///
  /// A JSON document (`schemaVersion`, account, settings, devices with design capacity and estimated full-charge capacity, daily usage, charging and monthly summaries, AI generation metadata, subscriptions), sent as an attachment `wattbyte-export-YYYY-MM-DD.json`. Never contains the password hash, sessions or refresh tokens, or another user's data. `?format=csv` returns only the daily usage as RFC 4180 `text/csv; charset=utf-8`. At most 10000 rows per collection (the newest); a cut collection is flagged in `limits.truncated` (CSV: header `x-wattbyte-truncated`).
  ///
  /// Parameters:
  ///
  /// * [String] format:
  Future<CloudExportDocument?> apiV1MeExportGet({
    String? format,
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1MeExportGetWithHttpInfo(
      format: format,
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
        'CloudExportDocument',
      ) as CloudExportDocument;
    }
    return null;
  }

  /// Performs an HTTP 'GET /api/v1/me' operation and returns the [Response].
  Future<Response> apiV1MeGetWithHttpInfo({
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/me';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

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

  Future<UserDto?> apiV1MeGet({
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1MeGetWithHttpInfo(
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
        'UserDto',
      ) as UserDto;
    }
    return null;
  }

  /// Change the password; every device is signed out and a fresh session is returned for this one
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [ChangePasswordRequest] changePasswordRequest (required):
  Future<Response> apiV1MePasswordPostWithHttpInfo(
    ChangePasswordRequest changePasswordRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/me/password';

    // ignore: prefer_final_locals
    Object? postBody = changePasswordRequest;

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

  /// Change the password; every device is signed out and a fresh session is returned for this one
  ///
  /// Parameters:
  ///
  /// * [ChangePasswordRequest] changePasswordRequest (required):
  Future<AuthResponse?> apiV1MePasswordPost(
    ChangePasswordRequest changePasswordRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1MePasswordPostWithHttpInfo(
      changePasswordRequest,
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
        'AuthResponse',
      ) as AuthResponse;
    }
    return null;
  }

  /// Performs an HTTP 'PATCH /api/v1/me' operation and returns the [Response].
  /// Parameters:
  ///
  /// * [UpdateMeRequest] updateMeRequest (required):
  Future<Response> apiV1MePatchWithHttpInfo(
    UpdateMeRequest updateMeRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/me';

    // ignore: prefer_final_locals
    Object? postBody = updateMeRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];

    return apiClient.invokeAPI(
      path,
      'PATCH',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Parameters:
  ///
  /// * [UpdateMeRequest] updateMeRequest (required):
  Future<UserDto?> apiV1MePatch(
    UpdateMeRequest updateMeRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1MePatchWithHttpInfo(
      updateMeRequest,
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
        'UserDto',
      ) as UserDto;
    }
    return null;
  }

  /// The devices that are signed in (one entry per sign-in), newest first
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> apiV1MeSessionsGetWithHttpInfo({
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/me/sessions';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

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

  /// The devices that are signed in (one entry per sign-in), newest first
  Future<SessionListResponse?> apiV1MeSessionsGet({
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1MeSessionsGetWithHttpInfo(
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
        'SessionListResponse',
      ) as SessionListResponse;
    }
    return null;
  }

  /// Sign one device out (its refresh tokens and access tokens stop working at once)
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  Future<Response> apiV1MeSessionsIdDeleteWithHttpInfo(
    String id, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/me/sessions/{id}'.replaceAll('{id}', id);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];

    return apiClient.invokeAPI(
      path,
      'DELETE',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Sign one device out (its refresh tokens and access tokens stop working at once)
  ///
  /// Parameters:
  ///
  /// * [String] id (required):
  Future<String?> apiV1MeSessionsIdDelete(
    String id, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1MeSessionsIdDeleteWithHttpInfo(
      id,
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
        'String',
      ) as String;
    }
    return null;
  }

  /// Account-level preferences (region, currency, electricity price mode) with the origin of each value; defaults before the first save
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> apiV1MeSettingsGetWithHttpInfo({
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/me/settings';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

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

  /// Account-level preferences (region, currency, electricity price mode) with the origin of each value; defaults before the first save
  Future<UserSettingsDto?> apiV1MeSettingsGet({
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1MeSettingsGetWithHttpInfo(
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
        'UserSettingsDto',
      ) as UserSettingsDto;
    }
    return null;
  }

  /// Update account-level preferences and the origin of each value; omitted fields keep their value
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [UpdateUserSettingsRequest] updateUserSettingsRequest (required):
  Future<Response> apiV1MeSettingsPutWithHttpInfo(
    UpdateUserSettingsRequest updateUserSettingsRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/me/settings';

    // ignore: prefer_final_locals
    Object? postBody = updateUserSettingsRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];

    return apiClient.invokeAPI(
      path,
      'PUT',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Update account-level preferences and the origin of each value; omitted fields keep their value
  ///
  /// Parameters:
  ///
  /// * [UpdateUserSettingsRequest] updateUserSettingsRequest (required):
  Future<UserSettingsDto?> apiV1MeSettingsPut(
    UpdateUserSettingsRequest updateUserSettingsRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1MeSettingsPutWithHttpInfo(
      updateUserSettingsRequest,
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
        'UserSettingsDto',
      ) as UserSettingsDto;
    }
    return null;
  }
}
