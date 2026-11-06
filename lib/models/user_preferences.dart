class UserPreferences {
  const UserPreferences({
    required this.language,
    required this.homePlace,
    required this.workPlace,
    required this.campusPlace,
    required this.musicAllowed,
    required this.smokingAllowed,
    required this.petsAllowed,
    required this.luggagePreference,
  });

  final String language;
  final String? homePlace;
  final String? workPlace;
  final String? campusPlace;
  final bool musicAllowed;
  final bool smokingAllowed;
  final bool petsAllowed;
  final String luggagePreference;

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        language: json['language'] as String? ?? 'en',
        homePlace: json['homePlace'] as String?,
        workPlace: json['workPlace'] as String?,
        campusPlace: json['campusPlace'] as String?,
        musicAllowed: json['musicAllowed'] as bool? ?? true,
        smokingAllowed: json['smokingAllowed'] as bool? ?? false,
        petsAllowed: json['petsAllowed'] as bool? ?? false,
        luggagePreference: json['luggagePreference'] as String? ?? 'standard',
      );

  Map<String, dynamic> toJson() => {
    'language': language,
    'homePlace': homePlace,
    'workPlace': workPlace,
    'campusPlace': campusPlace,
    'musicAllowed': musicAllowed,
    'smokingAllowed': smokingAllowed,
    'petsAllowed': petsAllowed,
    'luggagePreference': luggagePreference,
  };
}
