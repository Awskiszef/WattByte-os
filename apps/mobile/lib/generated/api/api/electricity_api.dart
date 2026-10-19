//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class ElectricityApi {
  ElectricityApi([ApiClient? apiClient])
      : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Average household electricity price per kWh for a country (defaults to the account country)
  ///
  /// A statistical average from a public source (Eurostat nrg_pc_204, band DC, taxes included), cached server-side. Never a wholesale or spot price and never the user's own tariff. 404 when no source covers the country.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] country:
  Future<Response> apiV1ElectricityPriceGetWithHttpInfo({
    String? country,
    Future<void>? abortTrigger,
  }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/v1/electricity-price';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (country != null) {
      queryParams.addAll(_queryParams('', 'country', country));
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

  /// Average household electricity price per kWh for a country (defaults to the account country)
  ///
  /// A statistical average from a public source (Eurostat nrg_pc_204, band DC, taxes included), cached server-side. Never a wholesale or spot price and never the user's own tariff. 404 when no source covers the country.
  ///
  /// Parameters:
  ///
  /// * [String] country:
  Future<ElectricityPriceDto?> apiV1ElectricityPriceGet({
    String? country,
    Future<void>? abortTrigger,
  }) async {
    final response = await apiV1ElectricityPriceGetWithHttpInfo(
      country: country,
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
        'ElectricityPriceDto',
      ) as ElectricityPriceDto;
    }
    return null;
  }
}
