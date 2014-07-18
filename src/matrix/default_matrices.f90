!==========================================================================!
!==========================================================================!
module default_matrices                                                    !
!==========================================================================!
!==========================================================================!
!====     This module contains the definition of the default           ====!
!==== implementation of sparse matrices. It uses no information about  ====!
!==== the underlying graph type other than what is provided by the     ====!
!==== graph interface. While it is very general, it is also not as     ====!
!==== fast as other, more specific implementations.                    ====!
!==========================================================================!
!==========================================================================!


use types, only: dp
use graph_interface
use default_sparse_matrix_kernels
use sparse_matrix_interface

implicit none




!--------------------------------------------------------------------------!
type, extends(sparse_matrix) :: default_matrix                             !
!--------------------------------------------------------------------------!
    class(graph), pointer :: g
    real(dp), allocatable :: val(:)


    !----------------
    ! The default implementation of a sparse matrix relies on several
    ! procedures defined in the module default_sparse_matrix_kernels.
    ! These are associated to each matrix through various function
    ! pointers.
    procedure(get_slice_kernel), pointer, nopass, private :: get_row_impl
    procedure(get_slice_kernel), pointer, nopass, private :: get_column_impl

    procedure(permute_kernel), pointer, nopass, private :: left_permute_impl
    procedure(permute_kernel), pointer, nopass, private :: right_permute_impl

contains
    !--------------
    ! Constructors
    !--------------
    procedure :: init => default_matrix_init


    !-----------
    ! Accessors
    !-----------
    procedure :: get_value => default_matrix_get_value
    procedure :: get_row => default_matrix_get_row
    procedure :: get_column => default_matrix_get_column


    !-----------------------
    ! Edge, value iterators
    !-----------------------
    procedure :: make_cursor => default_matrix_make_cursor
    procedure :: get_edges => default_matrix_get_edges
    procedure :: get_entries => default_matrix_get_entries


    !----------
    ! Mutators
    !----------
    procedure :: set_value => default_matrix_set_value
    procedure :: add_value => default_matrix_add_value
    procedure :: zero => default_matrix_zero
    procedure :: left_permute => default_matrix_left_permute
    procedure :: right_permute => default_matrix_right_permute
    procedure :: assemble => default_matrix_assemble
    procedure :: disassemble => default_matrix_disassemble


    !------------------------------
    ! Matrix-vector multiplication
    !------------------------------
    ! These procedures are provided by the parent class sparse_matrix.


    !-------------
    ! Destructors
    !-------------
    procedure :: destroy => default_matrix_destroy

end type default_matrix



interface default_matrix
    module procedure default_matrix_factory
end interface



contains





!==========================================================================!
!==== Constructors and factory methods                                 ====!
!==========================================================================!

!--------------------------------------------------------------------------!
function default_matrix_factory(nrow, ncol, g, orientation) result(A)      !
!--------------------------------------------------------------------------!
    integer, intent(in) :: nrow, ncol
    class(graph), pointer, intent(in) :: g
    character(len=3), intent(in) :: orientation
    class(sparse_matrix), pointer :: A

    allocate(default_matrix :: A)
    select type(A)
        class is(default_matrix)
            call A%init(nrow, ncol, g, orientation)
    end select

end function default_matrix_factory



!--------------------------------------------------------------------------!
subroutine default_matrix_init(A, nrow, ncol, g, orientation)              !
!--------------------------------------------------------------------------!
    class(default_matrix), intent(inout) :: A
    integer, intent(in) :: nrow, ncol
    class(graph), pointer, intent(in) :: g
    character(len=3), intent(in) :: orientation

    A%nrow = nrow
    A%ncol = ncol

    A%g => g

    call A%g%add_reference()

    A%nnz = A%g%ne
    allocate( A%val(A%g%capacity) )
    A%val = 0.0_dp

    ! Set the `ord` attribute for the matrix, so that the indices are
    ! reversed if we use column-major ordering and so the right kernels
    ! are selected for matvec, getting rows/columns, etc.
    select case(orientation)
        case('row')
            A%ord = [1, 2]

            A%get_row_impl    => get_slice_contiguous
            A%get_column_impl => get_slice_discontiguous

            A%left_permute_impl  => graph_leftperm
            A%right_permute_impl => graph_rightperm
        case('col')
            A%ord = [2, 1]

            A%get_row_impl    => get_slice_discontiguous
            A%get_column_impl => get_slice_contiguous

            A%left_permute_impl  => graph_rightperm
            A%right_permute_impl => graph_leftperm
    end select

end subroutine default_matrix_init




!==========================================================================!
!==== Accessors                                                        ====!
!==========================================================================!

!--------------------------------------------------------------------------!
function default_matrix_get_value(A, i, j) result(z)                       !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(default_matrix), intent(in) :: A
    integer, intent(in) :: i, j
    real(dp) :: z
    ! local variables
    integer :: k, ind(2)

    ! Reverse the indices (i,j) according to the ordering (row- or column-
    ! major) of the matrix
    ind(1) = i
    ind(2) = j
    ind = ind(A%ord)

    ! Set the return value to 0
    z = 0.0_dp

    ! Find the index k in A%g of the edge twixt (i, j)
    k = A%g%find_edge(ind(1), ind(2))

    ! If that edge exists, find the corresponding matrix entry & return it
    if (k /= -1) z = A%val(k)

end function default_matrix_get_value



!--------------------------------------------------------------------------!
subroutine default_matrix_get_row(A, nodes, slice, k)                      !
!--------------------------------------------------------------------------!
    class(default_matrix), intent(in) :: A
    integer, intent(out) :: nodes(:)
    real(dp), intent(out) :: slice(:)
    integer, intent(in) :: k

    call A%get_row_impl( A%g, A%val, nodes, slice, k)

end subroutine default_matrix_get_row



!--------------------------------------------------------------------------!
subroutine default_matrix_get_column(A, nodes, slice, k)                   !
!--------------------------------------------------------------------------!
    class(default_matrix), intent(in) :: A
    integer, intent(out) :: nodes(:)
    real(dp), intent(out) :: slice(:)
    integer, intent(in) :: k

    call A%get_column_impl( A%g, A%val, nodes, slice, k)

end subroutine default_matrix_get_column




!==========================================================================!
!==== Edge, value iterators                                            ====!
!==========================================================================!

!--------------------------------------------------------------------------!
function default_matrix_make_cursor(A) result(cursor)                      !
!--------------------------------------------------------------------------!
    class(default_matrix), intent(in) :: A
    type(graph_edge_cursor) :: cursor

    cursor = A%g%make_cursor()

end function default_matrix_make_cursor



!--------------------------------------------------------------------------!
subroutine default_matrix_get_edges(A, edges, cursor, &                    !
                                                & num_edges, num_returned) !
!--------------------------------------------------------------------------!
    class(default_matrix), intent(in) :: A
    integer, intent(out) :: edges(2, num_edges)
    type(graph_edge_cursor), intent(inout) :: cursor
    integer, intent(in) :: num_edges
    integer, intent(out) :: num_returned

    ! Get a batch of edges from the connectivity graph of A
    call A%g%get_edges(edges, cursor, num_edges, num_returned)

    ! Reverse the edges if A is in column-major order
    !TODO: See if we can do this without making a temporary array and if
    ! that's any faster
    edges = edges(A%ord, :)

end subroutine default_matrix_get_edges



!--------------------------------------------------------------------------!
subroutine default_matrix_get_entries(A, edges, entries, cursor, &         !
                                                & num_edges, num_returned) !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(default_matrix), intent(in) :: A
    integer, intent(out) :: edges(2, num_edges)
    real(dp), intent(out) :: entries(num_edges)
    type(graph_edge_cursor), intent(inout) :: cursor
    integer, intent(in) :: num_edges
    integer, intent(out) :: num_returned
    ! local variables
    integer :: indx

    ! Store the current position of the cursor
    indx = cursor%current

    ! Get the next batch of edges from A without the values
    call A%get_edges(edges, cursor, num_edges, num_returned)

    ! Get the entries from A
    entries = 0.0_dp
    entries(1 : num_returned) = A%val(indx + 1 : indx + num_returned)

end subroutine default_matrix_get_entries




!==========================================================================!
!==== Mutators                                                         ====!
!==========================================================================!

!--------------------------------------------------------------------------!
subroutine default_matrix_set_value(A, i, j, z)                            !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(default_matrix), intent(inout) :: A
    integer, intent(in) :: i, j
    real(dp), intent(in) :: z
    ! local variables
    integer :: k, ind(2)

    ind(1) = i
    ind(2) = j
    ind = ind(A%ord)

    k = A%g%find_edge(ind(1), ind(2))

    if (k /= -1) then
        A%val(k) = z
    else
        call set_matrix_value_with_reallocation(A%g, A%val, &
                                                    & ind(1), ind(2), z)
        A%nnz = A%nnz + 1
    endif

end subroutine default_matrix_set_value



!--------------------------------------------------------------------------!
subroutine default_matrix_add_value(A, i, j, z)                            !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(default_matrix), intent(inout) :: A
    integer, intent(in) :: i, j
    real(dp), intent(in) :: z
    ! local variables
    integer :: k, ind(2)

    ind(1) = i
    ind(2) = j
    ind = ind(A%ord)

    k = A%g%find_edge(ind(1), ind(2))

    if (k /= -1) then
        A%val(k) = A%val(k) + z
    else
        call set_matrix_value_with_reallocation(A%g, A%val, &
                                                        & ind(1), ind(2), z)
        A%nnz = A%nnz + 1
    endif

end subroutine default_matrix_add_value



!--------------------------------------------------------------------------!
subroutine default_matrix_zero(A)                                          !
!--------------------------------------------------------------------------!
    class(default_matrix), intent(inout) :: A

    A%val = 0.0_dp

end subroutine default_matrix_zero



!--------------------------------------------------------------------------!
subroutine default_matrix_left_permute(A, p)                               !
!--------------------------------------------------------------------------!
    class(default_matrix), intent(inout) :: A
    integer, intent(in) :: p(:)

    call A%left_permute_impl(A%g, A%val, p)

end subroutine default_matrix_left_permute



!--------------------------------------------------------------------------!
subroutine default_matrix_right_permute(A, p)                              !
!--------------------------------------------------------------------------!
    class(default_matrix), intent(inout) :: A
    integer, intent(in) :: p(:)

    call A%right_permute_impl(A%g, A%val, p)

end subroutine default_matrix_right_permute



!--------------------------------------------------------------------------!
subroutine default_matrix_assemble(A)                                      !
!--------------------------------------------------------------------------!
    class(default_matrix), intent(inout) :: A

    ! Defer to a routine in default_sparse_matrix_kernels
    call assemble_matrix(A%g, A%val)

    A%assembled = .true.

end subroutine default_matrix_assemble



!--------------------------------------------------------------------------!
subroutine default_matrix_disassemble(A)                                   !
!--------------------------------------------------------------------------!
    class(default_matrix), intent(inout) :: A

    call A%g%decompress()

    A%assembled = .false.

end subroutine default_matrix_disassemble




!==========================================================================!
!==== Matrix-vector multiplication                                     ====!
!==========================================================================!

! The parent sparse matrix class provides a default, if not very optimal,
! implementation of these methods. The interface to the procedure is below
! but commented out, for the user who wishes to copy this module and use it
! as a guide to making her/his own matrix implementation.

!--------------------------------------------------------------------------!
! subroutine default_matrix_matvec_add(A, x, y)                            !
!--------------------------------------------------------------------------!
!     class(cs_matrix), intent(in) :: A                                    !
!     real(dp), intent(in)    :: x(:)                                      !
!     real(dp), intent(inout) :: y(:)                                      !
!                                                                          !
!     << Your implementation goes here >>                                  !
!                                                                          !
! end subroutine default_matrix_matvec_add                                 !
!--------------------------------------------------------------------------!



!--------------------------------------------------------------------------!
! subroutine default_matrix_matvec_t_add(A, x, y)                          !
!--------------------------------------------------------------------------!
!     class(cs_matrix), intent(in) :: A                                    !
!     real(dp), intent(in)    :: x(:)                                      !
!     real(dp), intent(inout) :: y(:)                                      !
!                                                                          !
!     << Your implementation goes here >>                                  !
!                                                                          !
! end subroutine default_matrix_matvec_t_add                               !
!--------------------------------------------------------------------------!




!==========================================================================!
!==== Destructors                                                      ====!
!==========================================================================!

!--------------------------------------------------------------------------!
subroutine default_matrix_destroy(A)                                       !
!--------------------------------------------------------------------------!
    class(default_matrix), intent(inout) :: A

    ! Deallocate the array of A's matrix entries
    deallocate(A%val)

    ! Decrement the reference counter for A%g
    call A%g%remove_reference()

    ! Nullify A's pointer to its graph. Don't de-allocate it -- there might
    ! still be other references to it someplace else.
    nullify(A%g)

end subroutine default_matrix_destroy



end module default_matrices
