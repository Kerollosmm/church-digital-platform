import '../repositories/booking_repository.dart';
import '../repositories/supabase_booking_repository.dart';
import 'app_supabase.dart';

class AppDependencies {
  AppDependencies({required this.supabase, required this.bookingRepository});
  final AppSupabase supabase;
  final BookingRepository bookingRepository;

  factory AppDependencies.forTest({
    AppSupabase? supabase,
    BookingRepository? bookingRepository,
  }) => AppDependencies(
    supabase: supabase ?? UnimplementedAppSupabase(),
    bookingRepository: bookingRepository ?? EmptyBookingRepository(),
  );
}
