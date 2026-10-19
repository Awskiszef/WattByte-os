//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class AuthApi {
  AuthApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Sign in with Apple (not configured yet)
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [ApiV1AuthApplePostRequest] apiV1AuthApplePostRequest (required):
  Future<Response> apiV1AuthApplePostWithHttpInfo(
    ApiV1AuthApplePostRequest apiV1AuthApplePostRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/apple';

    // ignore: prefer_final_locals
    Object? postBody = apiV1AuthApplePostRequest;

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

  /// Sign in with Apple (not configured yet)
  ///
  /// Parameters:
  ///
  /// * [ApiV1AuthApplePostRequest] apiV1AuthApplePostRequest (required):
  Future<AuthResponse?> apiV1AuthApplePost(
    ApiV1AuthApplePostRequest apiV1AuthApplePostRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1AuthApplePostWithHttpInfo(
      apiV1AuthApplePostRequest,
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

  /// Sign in with Google (not configured yet)
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [ApiV1AuthApplePostRequest] apiV1AuthApplePostRequest (required):
  Future<Response> apiV1AuthGooglePostWithHttpInfo(
    ApiV1AuthApplePostRequest apiV1AuthApplePostRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/google';

    // ignore: prefer_final_locals
    Object? postBody = apiV1AuthApplePostRequest;

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

  /// Sign in with Google (not configured yet)
  ///
  /// Parameters:
  ///
  /// * [ApiV1AuthApplePostRequest] apiV1AuthApplePostRequest (required):
  Future<AuthResponse?> apiV1AuthGooglePost(
    ApiV1AuthApplePostRequest apiV1AuthApplePostRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1AuthGooglePostWithHttpInfo(
      apiV1AuthApplePostRequest,
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

  /// Performs an HTTP 'POST /api/v1/auth/login' operation and returns the [Response].
  /// Parameters:
  ///
  /// * [LoginRequest] loginRequest (required):
  Future<Response> apiV1AuthLoginPostWithHttpInfo(
    LoginRequest loginRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/login';

    // ignore: prefer_final_locals
    Object? postBody = loginRequest;

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

  /// Parameters:
  ///
  /// * [LoginRequest] loginRequest (required):
  Future<AuthResponse?> apiV1AuthLoginPost(
    LoginRequest loginRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1AuthLoginPostWithHttpInfo(
      loginRequest,
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

  /// Performs an HTTP 'POST /api/v1/auth/logout' operation and returns the [Response].
  /// Parameters:
  ///
  /// * [RefreshRequest] refreshRequest (required):
  Future<Response> apiV1AuthLogoutPostWithHttpInfo(
    RefreshRequest refreshRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/logout';

    // ignore: prefer_final_locals
    Object? postBody = refreshRequest;

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

  /// Parameters:
  ///
  /// * [RefreshRequest] refreshRequest (required):
  Future<String?> apiV1AuthLogoutPost(
    RefreshRequest refreshRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1AuthLogoutPostWithHttpInfo(
      refreshRequest,
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

  /// Exchange a refresh token for a new pair (rotation)
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [RefreshRequest] refreshRequest (required):
  Future<Response> apiV1AuthRefreshPostWithHttpInfo(
    RefreshRequest refreshRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/refresh';

    // ignore: prefer_final_locals
    Object? postBody = refreshRequest;

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

  /// Exchange a refresh token for a new pair (rotation)
  ///
  /// Parameters:
  ///
  /// * [RefreshRequest] refreshRequest (required):
  Future<AuthResponse?> apiV1AuthRefreshPost(
    RefreshRequest refreshRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1AuthRefreshPostWithHttpInfo(
      refreshRequest,
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

  /// Create an email + password account
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [RegisterRequest] registerRequest (required):
  Future<Response> apiV1AuthRegisterPostWithHttpInfo(
    RegisterRequest registerRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/auth/register';

    // ignore: prefer_final_locals
    Object? postBody = registerRequest;

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

  /// Create an email + password account
  ///
  /// Parameters:
  ///
  /// * [RegisterRequest] registerRequest (required):
  Future<AuthResponse?> apiV1AuthRegisterPost(
    RegisterRequest registerRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1AuthRegisterPostWithHttpInfo(
      registerRequest,
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
}
