module csr_matrices

use sparse_matrices
use cs_graphs

implicit none



!--------------------------------------------------------------------------!
type, extends(sparse_matrix) :: csr_matrix                                 !
!--------------------------------------------------------------------------!
    real(dp), allocatable :: val(:)
    class(cs_graph), pointer :: g
contains
    procedure :: init => csr_init
    procedure :: assemble => csr_assemble
    procedure :: neighbors => csr_matrix_neighbors
    procedure :: get_value => csr_get_value
    procedure :: set_value => csr_set_value, add_value => csr_add_value
    procedure :: sub_matrix_add => csr_sub_matrix_add
    procedure :: left_permute => csr_left_permute, &
                & right_permute => csr_right_permute
    procedure :: matvec => csr_matvec, matvec_t => csr_matvec_t
    procedure, private :: csr_set_value_not_preallocated
end type csr_matrix



!!--------------------------------------------------------------------------!
!type, extends(sparse_matrix) :: csc_matrix                                 !
!!--------------------------------------------------------------------------!
!    real(dp), allocatable :: val(:)
!    class(cs_graph), pointer :: g
!contains
!    procedure :: init => csr_init
!    procedure :: assemble => csc_assemble
!    procedure :: neighbors => csr_matrix_neighbors
!    procedure :: get_value => csc_get_value
!    procedure :: set_value => csc_set_value, add_value => csc_add_value
!    procedure :: matvec => csr_matvec_t, matvec_t => csr_matvec
!    procedure, private :: csc_set_value_not_preallocated
!end type csc_matrix




contains





!--------------------------------------------------------------------------!
subroutine csr_init(A,nrow,ncol)                                           !
!--------------------------------------------------------------------------!
    class(csr_matrix), intent(inout) :: A
    integer, intent(in) :: nrow, ncol

    A%nrow = nrow
    A%ncol = ncol
    A%max_degree = 0

end subroutine csr_init



!--------------------------------------------------------------------------!
subroutine csr_assemble(A,g)                                               !
!--------------------------------------------------------------------------!
    class(csr_matrix), intent(inout) :: A
    class(cs_graph), pointer, intent(in) :: g

    A%g => g

    A%nrow = g%n
    A%ncol = g%m
    A%nnz = g%ne
    A%max_degree = g%max_degree

    allocate(A%val(A%nnz))
    A%val = 0.0_dp

end subroutine csr_assemble



!--------------------------------------------------------------------------!
subroutine csr_matrix_neighbors(A,i,nbrs)                                  !
!--------------------------------------------------------------------------!
    class(csr_matrix), intent(in) :: A
    integer, intent(in)  :: i
    integer, intent(out) :: nbrs(:)

    nbrs = 0
    call A%g%neighbors(i,nbrs)

end subroutine csr_matrix_neighbors



!--------------------------------------------------------------------------!
function csr_get_value(A,i,j)                                              !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(csr_matrix), intent(in) :: A
    integer, intent(in) :: i,j
    real(dp) :: csr_get_value
    ! local variables
    integer :: k

    csr_get_value = 0_dp
    k = A%g%find_edge(i,j)
    if (k/=-1) csr_get_value = A%val(k)

end function csr_get_value



!--------------------------------------------------------------------------!
subroutine csr_set_value(A,i,j,val)                                        !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(csr_matrix), intent(inout) :: A
    integer, intent(in) :: i,j
    real(dp), intent(in) :: val
    ! local variables
    integer :: k

    k = A%g%find_edge(i,j)
    if (k/=-1) then
        A%val(k) = val
    else
        call A%csr_set_value_not_preallocated(i,j,val)
    endif

end subroutine csr_set_value



!--------------------------------------------------------------------------!
subroutine csr_add_value(A,i,j,val)                                        !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(csr_matrix), intent(inout) :: A
    integer, intent(in) :: i,j
    real(dp), intent(in) :: val
    ! local variables
    integer :: k

    k = A%g%find_edge(i,j)
    if (k/=-1) then
        A%val(k) = A%val(k)+val
    else
        call A%csr_set_value_not_preallocated(i,j,val)
    endif

end subroutine csr_add_value



!--------------------------------------------------------------------------!
subroutine csr_sub_matrix_add(A,B)                                         !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(csr_matrix), intent(inout) :: A
    class(csr_matrix), intent(in)    :: B
    ! local variables
    integer :: i,j,k,indx,nbrs(B%max_degree)

    do i=1,B%nrow
        do k=B%g%ia(i),B%g%ia(i+1)-1
            j = B%g%ja(k)
            indx = A%g%find_edge(i,j)
            A%val(indx) = A%val(indx)+B%val(k)
        enddo
    enddo

end subroutine csr_sub_matrix_add



!--------------------------------------------------------------------------!
subroutine csr_left_permute(A,p)                                           !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(csr_matrix), intent(inout) :: A
    integer, intent(in) :: p(:)
    ! local variables
    integer :: i,k,ia(A%g%n+1)
    real(dp) :: val(A%nnz)

    do i=1,A%g%n
        ia(p(i)+1) = A%g%ia(i+1)-A%g%ia(i)
    enddo

    ia(1) = 1
    do i=1,A%g%n
        ia(i+1) = ia(i+1)+ia(i)
    enddo

    do i=1,A%g%n
        do k=0,A%g%ia(i+1)-A%g%ia(i)-1
            val( ia(p(i))+k ) = A%val( A%g%ia(i)+k )
        enddo
    enddo

    A%val = val

    call A%g%left_permute(p)

end subroutine csr_left_permute



!--------------------------------------------------------------------------!
subroutine csr_right_permute(A,p)                                          !
!--------------------------------------------------------------------------!
    class(csr_matrix), intent(inout) :: A
    integer, intent(in) :: p(:)

    call A%g%right_permute(p)

end subroutine csr_right_permute



!--------------------------------------------------------------------------!
subroutine csr_matvec(A,x,y)                                               !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(csr_matrix), intent(in) :: A
    real(dp), intent(in)  :: x(:)
    real(dp), intent(out) :: y(:)
    ! local variables
    integer :: i,j,k
    real(dp) :: z

    do i=1,A%g%n
        z = 0_dp
        do k=A%g%ia(i),A%g%ia(i+1)-1
            j = A%g%ja(k)
            z = z+A%val(k)*x(j)
        enddo
        y(i) = z
    enddo

end subroutine csr_matvec



!--------------------------------------------------------------------------!
subroutine csr_matvec_t(A,x,y)                                             !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(csr_matrix), intent(in) :: A
    real(dp), intent(in)  :: x(:)
    real(dp), intent(out) :: y(:)
    ! local variables
    integer :: i,j,k
    real(dp) :: z

    do i=1,A%g%n
        z = x(i)
        do k=A%g%ia(i),A%g%ia(i+1)-1
            j = A%g%ja(k)
            y(j) = y(j)+A%val(k)*z
        enddo
    enddo

end subroutine csr_matvec_t



!--------------------------------------------------------------------------!
subroutine csr_set_value_not_preallocated(A,i,j,val)                       !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(csr_matrix), intent(inout) :: A
    integer, intent(in) :: i,j
    real(dp), intent(in) :: val
    ! local variables
    real(dp) :: val_temp(A%nnz)
    integer :: k

    call A%g%add_edge(i,j)
    k = A%g%find_edge(i,j)
    val_temp = A%val
    deallocate(A%val)
    allocate(A%val(A%nnz+1))
    A%val(1:k-1) = val_temp(1:k-1)
    A%val(k) = val
    A%val(k+1:A%nnz+1) = val_temp(k:A%nnz)
    A%nnz = A%nnz+1
    A%max_degree = A%g%max_degree

end subroutine csr_set_value_not_preallocated




end module csr_matrices