//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class DevicesApi {
  DevicesApi([ApiClient? apiClient])
      : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Performs an HTTP 'GET /api/v1/devices' operation and returns the [Response].
  Future<Response> apiV1DevicesGetWithHttpInfo({
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/devices';

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

  Future<DeviceListResponse?> apiV1DevicesGet({
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1DevicesGetWithHttpInfo(
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
        'DeviceListResponse',
      ) as DeviceListResponse;
    }
    return null;
  }

  /// Performs an HTTP 'DELETE /api/v1/devices/{id}' operation and returns the [Response].
  /// Parameters:
  ///
  /// * [String] id (required):
  Future<Response> apiV1DevicesIdDeleteWithHttpInfo(
    String id, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/devices/{id}'.replaceAll('{id}', id);

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

  /// Parameters:
  ///
  /// * [String] id (required):
  Future<String?> apiV1DevicesIdDelete(
    String id, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1DevicesIdDeleteWithHttpInfo(
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

  /// Register (or refresh) this installation; idempotent per installationId
  ///
  /// An account holds at most MAX_DEVICES_PER_ACCOUNT installations: registering one more answers 409 device_limit_reached (delete an old device with DELETE /devices/{id}); refreshing an installation the account already has always works. Battery capacity travels in two groups that are stored atomically: the design capacity of the model (designCapacityMah / designCapacityWh / designCapacitySource) and the estimated full-charge capacity of this battery (estimatedFullChargeCapacityMah / estimatedFullChargeCapacityWh / fullChargeCapacitySource / fullChargeCapacityConfidence). A group whose source is given replaces the stored group as a whole (nulls included); a group with a null source leaves the stored one untouched. A design capacity needs a source other than unknown; an estimate needs source androidChargeCounter and a confidence; Wh needs mAh. Violations are 400 validation.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [DeviceRegisterRequest] deviceRegisterRequest (required):
  Future<Response> apiV1DevicesPostWithHttpInfo(
    DeviceRegisterRequest deviceRegisterRequest, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/devices';

    // ignore: prefer_final_locals
    Object? postBody = deviceRegisterRequest;

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

  /// Register (or refresh) this installation; idempotent per installationId
  ///
  /// An account holds at most MAX_DEVICES_PER_ACCOUNT installations: registering one more answers 409 device_limit_reached (delete an old device with DELETE /devices/{id}); refreshing an installation the account already has always works. Battery capacity travels in two groups that are stored atomically: the design capacity of the model (designCapacityMah / designCapacityWh / designCapacitySource) and the estimated full-charge capacity of this battery (estimatedFullChargeCapacityMah / estimatedFullChargeCapacityWh / fullChargeCapacitySource / fullChargeCapacityConfidence). A group whose source is given replaces the stored group as a whole (nulls included); a group with a null source leaves the stored one untouched. A design capacity needs a source other than unknown; an estimate needs source androidChargeCounter and a confidence; Wh needs mAh. Violations are 400 validation.
  ///
  /// Parameters:
  ///
  /// * [DeviceRegisterRequest] deviceRegisterRequest (required):
  Future<DeviceDto?> apiV1DevicesPost(
    DeviceRegisterRequest deviceRegisterRequest, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1DevicesPostWithHttpInfo(
      deviceRegisterRequest,
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
        'DeviceDto',
      ) as DeviceDto;
    }
    return null;
  }

  /// Design (nominal) battery capacity for a model identifier (iOS utsname.machine or Android Build.MODEL)
  ///
  /// Served from the shared device catalog (packages/device-specs); every figure is a design capacity of the model, never a measurement. 404 when the model is not listed; the app then reports the capacity as unknown rather than guessing.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] identifier (required):
  Future<Response> apiV1DevicesSpecificationsIdentifierGetWithHttpInfo(
    String identifier, {
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/devices/specifications/{identifier}'
        .replaceAll('{identifier}', identifier);

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

  /// Design (nominal) battery capacity for a model identifier (iOS utsname.machine or Android Build.MODEL)
  ///
  /// Served from the shared device catalog (packages/device-specs); every figure is a design capacity of the model, never a measurement. 404 when the model is not listed; the app then reports the capacity as unknown rather than guessing.
  ///
  /// Parameters:
  ///
  /// * [String] identifier (required):
  Future<DeviceSpecificationDto?> apiV1DevicesSpecificationsIdentifierGet(
    String identifier, {
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1DevicesSpecificationsIdentifierGetWithHttpInfo(
      identifier,
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
        'DeviceSpecificationDto',
      ) as DeviceSpecificationDto;
    }
    return null;
  }
}
