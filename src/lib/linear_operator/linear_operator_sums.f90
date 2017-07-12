module linear_operator_sums

use types, only: dp
use linear_operator_interface

implicit none



!--------------------------------------------------------------------------!
type, extends(linear_operator) :: operator_sum                             !
!--------------------------------------------------------------------------!
    integer :: num_summands
    type(linear_operator_pointer), allocatable :: summands(:)
contains
    procedure :: get_value => operator_sum_get_value
    procedure :: matvec_add => operator_sum_matvec_add
    procedure :: matvec_t_add => operator_sum_matvec_t_add
    procedure :: destroy => operator_sum_destroy
end type operator_sum



!--------------------------------------------------------------------------!
interface operator(+)                                                      !
!--------------------------------------------------------------------------!
    module procedure add_operators
end interface



contains




!--------------------------------------------------------------------------!
function add_operators(A, B) result(C)                                     !
!--------------------------------------------------------------------------!
    class(linear_operator), target, intent(in) :: A, B
    class(linear_operator), pointer :: C

    ! Do some error checking
    if (A%nrow /= B%nrow .or. A%ncol /= B%ncol) then
        print *, 'Dimensions of operators to be summed are not consistent'
        call exit(1)
    endif

    ! Make a pointer to an operator_sum
    allocate(operator_sum::C)

    ! Set the dimension of C
    C%nrow = A%nrow
    C%ncol = A%ncol

    ! Make the summands of C point to A and B
    select type(C)
        type is(operator_sum)
            C%num_summands = 2
            allocate(C%summands(2))

            ! Make the operator_sum point to its two summands
            C%summands(1)%ap => A
            C%summands(2)%ap => B
            call C%summands(1)%ap%add_reference()
            call C%summands(2)%ap%add_reference()
    end select

end function add_operators



!--------------------------------------------------------------------------!
function operator_sum_get_value(A, i, j) result(z)                         !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(operator_sum), intent(in) :: A
    integer, intent(in) :: i, j
    real(dp) :: z
    ! local variables
    integer :: k

    z = 0.0_dp

    do k = 1, A%num_summands
        z = z + A%summands(k)%ap%get_value(i, j)
    enddo

end function operator_sum_get_value



!--------------------------------------------------------------------------!
subroutine operator_sum_matvec_add(A, x, y)                                !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(operator_sum), intent(in) :: A
    real(dp), intent(in) :: x(:)
    real(dp), intent(inout) :: y(:)
    ! local variables
    integer :: k

    do k = 1, A%num_summands
        call A%summands(k)%ap%matvec_add(x, y)
    enddo

end subroutine operator_sum_matvec_add



!--------------------------------------------------------------------------!
subroutine operator_sum_matvec_t_add(A, x, y)                              !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(operator_sum), intent(in) :: A
    real(dp), intent(in) :: x(:)
    real(dp), intent(inout) :: y(:)
    ! local variables
    integer :: k

    do k = 1, A%num_summands
        call A%summands(k)%ap%matvec_t_add(x, y)
    enddo

end subroutine operator_sum_matvec_t_add



!--------------------------------------------------------------------------!
subroutine operator_sum_destroy(A)                                         !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(operator_sum), intent(inout) :: A
    ! local variables
    integer :: k

    ! Decrement the reference count for each summand, and destroy it if the
    ! reference count is 0
    do k = 1, A%num_summands
        call A%summands(k)%ap%remove_reference()

        if (A%summands(k)%ap%reference_count <= 0) then
            call A%summands(k)%ap%destroy()
            deallocate(A%summands(k)%ap)
        endif
    enddo

    do k = 1, A%num_summands
        nullify(A%summands(k)%ap)
    enddo

    deallocate(A%summands)

    A%reference_count = 0
    A%num_summands = 0

end subroutine operator_sum_destroy



end module linear_operator_sums

