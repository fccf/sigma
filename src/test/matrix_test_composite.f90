!--------------------------------------------------------------------------!
program matrix_test_composite                                              !
!--------------------------------------------------------------------------!
!     This program tests using the type sparse_matrix as a composite of    !
! several other sparse matrices, i.e. a block matrix. Each of the sub-     !
! matrices of the composite could be one of the primitive matrix formats,  !
! like CSC or ellpack, or could itself be a composite matrix.              !
!     Using sparse_matrix objects in this fashion allows the user to       !
! cleanly generate independent sub-blocks of a large matrix (possibly in   !
! parallel) and lace them together later.                                  !
!--------------------------------------------------------------------------!

use sigma

implicit none

    ! graph used as the matrix substrate
    class(graph_interface), pointer :: g1, g2, h, ht

    ! sparse matrix objects
    type(sparse_matrix) :: A
    class(sparse_matrix_interface), pointer :: C

    ! vectors
    real(dp), allocatable :: x(:), y(:), z(:)
    real(dp) :: mse, correct_val

    ! integer indices
    integer :: i, j, k, d, d1, d2, nn, nn1, nn2

    ! variables for getting matrix rows / columns
    integer, allocatable :: nodes(:), nodes1(:), nodes2(:)
    real(dp), allocatable :: slice(:)

    ! variables for testing matrix value iterators
    type(graph_edge_cursor) :: cursor
    integer :: num_returned, edges(2, batch_size)
    real(dp) :: vals(batch_size)

    ! random numbers
    real(dp) :: p, q

    ! command-line argument parsing
    character(len=16) :: arg
    logical :: verbose



    !----------------------------------------------------------------------!
    ! Get command line arguments to see if we're running in verbose mode   !
    !----------------------------------------------------------------------!

    verbose = .false.
    call getarg(1,arg)
    select case(trim(arg))
        case("-v")
            verbose = .true.
        case("-V")
            verbose = .true.
        case("--verbose")
            verbose = .true.
    end select

    call init_seed()



    !----------------------------------------------------------------------!
    ! Set the problem dimensions                                           !
    !----------------------------------------------------------------------!

    nn1 = 768
    nn2 = 512

    nn = nn1 + nn2

    allocate( x(nn), y(nn), z(nn) )

    call random_number(x)
    y = 0.0_dp
    z = 0.0_dp



    !----------------------------------------------------------------------!
    ! Initialize a sparse matrix composite                                 !
    !----------------------------------------------------------------------!

    call A%set_dimensions(nn, nn)
    call A%set_block_sizes( [nn1, nn2], [nn1, nn2] )

    if (A%num_row_mats /= 2 .or. A%num_col_mats /= 2) then
        print *, "Setting number of blocks of sparse matrix failed, should"
        print *, "have number of row & column blocks be 2 x 2."
        print *, "Values found:", A%num_row_mats, A%num_col_mats
        call exit(1)
    endif

    if (verbose) then
        print *, "o Composite sparse matrix initialized."
    endif



    !----------------------------------------------------------------------!
    ! Make a random Laplacian matrix                                       !
    !----------------------------------------------------------------------!

    ! Make the graph for the (1, 1)-submatrix of `A`
    p = log(1.0_dp * nn1) / log(2.0_dp) / nn1
    call choose_graph_type(g1, "ll")
    call erdos_renyi_graph(g1, nn1, nn1, p, symmetric = .true.)

    d = g1%get_max_degree()

    if (verbose) then
        print *, "o Done generating first Erdos-Renyi graph."
        print *, "    Number of vertices: ", nn1
        print *, "    Number of edges:    ", g1%get_num_edges()
        print *, "    Maximum degree:     ", d
    endif

    ! Make a Laplacian matrix on the graph with random weights
    call choose_matrix_type(C, "csr")
    call erdos_renyi_matrix(C, g1)

    if (verbose) then
        print *, "o Done generating first random weighted Laplacian matrix."
    endif

    ! Set the (1, 1)-submatrix of `A` to be `C`
    call A%set_submatrix(1, 1, C)

    ! Nullify `C` so that we can use it to build another sub-matrix
    call C%remove_reference()
    nullify(C)


    ! Do the same thing again for the (2, 2)-submatrix of `A`
    call choose_graph_type(g2, "ll")
    p = log(1.0_dp * nn2) / log(2.0_dp) / nn2

    call erdos_renyi_graph(g2, nn2, nn2, p, symmetric = .true.)
    d = g2%get_max_degree()

    if (verbose) then
        print *, "o Done generating second Erdos-Renyi graph."
        print *, "    Number of vertices: ", nn2
        print *, "    Number of edges:    ", g2%get_num_edges()
        print *, "    Maximum degree:     ", d
    endif

    call choose_matrix_type(C, "csr")
    call erdos_renyi_matrix(C, g2)

    if (verbose) then
        print *, "o Done generating second random weighted Laplacian matrix."
    endif

    call A%set_submatrix(2, 2, C)

    call C%remove_reference()
    nullify(C)


    ! Now generate a graph for the (1, 2)-submatrix
    p = 6.0 / nn1
    call choose_graph_type(h, "ll")
    call erdos_renyi_graph(h, nn1, nn2, p, symmetric = .false.)

    ! Convert it to CS storage
    call convert_graph_type(h, "cs")

    ! Make the (1, 2)-submatrix of `A` a CSR matrix,
    call A%set_matrix_type(1, 2, "csr")

    ! then *set* its graph to point to `g`.
    call A%set_graph_submat(1, 2, h)

    ! Now make the (2, 1)-submatrix of `A` a CSC matrix,
    call A%set_matrix_type(2, 1, "csc")

    ! and set its graph to point to `g` also.
    call A%set_graph_submat(2, 1, h)

    ! There are now 3 references to `g`: one from us having created it in
    ! the first place, another from the (1, 2)-submatrix of `A`, and a
    ! third from the (2, 1)-submatrix!
    ! This sounds a little complicated, but it means that we've saved some
    ! memory usage by having two matrices share an object -- the graph g --
    ! rather than duplicate it.
    if (verbose) then
        print *, "o Done creating couplings between (1, 1)- and (2, 2)-"
        print *, "  blocks of A via another random graph h."
        print *, "  Number of references to h:", h%reference_count
    endif

    ! Fill in all the matrix entries that couple the two fields
    d = h%get_max_degree()
    allocate(nodes(d))

    do i = 1, nn1

        d = h%get_degree(i)
        call h%get_neighbors(nodes, i)

        do k = 1, d
            j = nodes(k)

            call A%set(1, 2, i, j, -1.0_dp)
            call A%set(2, 1, j, i, -1.0_dp)
            call A%add(1, 1, i, i, +1.0_dp)
            call A%add(2, 2, j, j, +1.0_dp)
        enddo

    enddo

    deallocate(nodes)



    !----------------------------------------------------------------------!
    ! Test that all of the entries of `A` were set properly                !
    !----------------------------------------------------------------------!

    call choose_graph_type(ht, "cs")
    call ht%copy(h, trans = .true.)

    do i = 1, nn1
        do j = 1, nn1
            q = A%get(1, 1, i, j)
            correct_val = 0.0_dp

            if (j == i) then
                correct_val = g1%get_degree(i) + h%get_degree(i) - 1.0_dp
            else
                if (g1%connected(i, j)) correct_val = -1.0_dp
            endif

            if (dabs(q - correct_val) > 1.0e-15) then
                call wrong_matrix_entry_error(1, 1, i, j, correct_val, q)
            endif
        enddo


        do j = 1, nn2
            correct_val = 0.0_dp

            if (h%connected(i, j)) then
                correct_val = -1.0_dp
            endif

            q = A%get(1, 2, i, j)
            if (dabs(q - correct_val) > 1.0e-15) then
                call wrong_matrix_entry_error(1, 2, i, j, correct_val, q)
            endif

            q = A%get(2, 1, j, i)

            if (dabs(q - correct_val) > 1.0e-15) then
                call wrong_matrix_entry_error(2, 1, j, i, correct_val, q)
            endif
        enddo
    enddo


    do i = 1, nn2
        do j = 1, nn2
            q = A%get(2, 2, i, j)
            correct_val = 0.0_dp

            if (j == i) then
                correct_val = g2%get_degree(i) + ht%get_degree(i) - 1.0_dp
            else
                if (g2%connected(i, j)) correct_val = -1.0_dp
            endif

            if ( dabs(q - correct_val) > 1.0e-15 ) then
                call wrong_matrix_entry_error(2, 2, i, j, correct_val, q)
            endif
        enddo
    enddo

    if (verbose) then
        print *, "o Done checking entries of A."
    endif



    !----------------------------------------------------------------------!
    ! Test getting the degrees of each row / column of the matrix          !
    !----------------------------------------------------------------------!

    do k = 1, nn1
        d = A%get_row_degree(k)

        if (d /= g1%get_degree(k) + h%get_degree(k)) then
            print *, "Wrong row degree", k
            call exit(1)
        endif


        d = A%get_column_degree(k)

        if (d /= g1%get_degree(k) + h%get_degree(k)) then
            print *, "Wrong column degree", k
            call exit(1)
        endif
    enddo

    do k = 1, nn2
        d = A%get_row_degree(k + nn1)

        if (d /= g2%get_degree(k) + ht%get_degree(k)) then
            print *, "Wrong row degree", k + nn1
            call exit(1)
        endif


        d = A%get_column_degree(k + nn1)

        if (d /= g2%get_degree(k) + ht%get_degree(k)) then
            print *, "Wrong column degree", k + nn1
            call exit(1)
        endif
    enddo

    if (verbose) then
        print *, "o Done checking the degrees of the rows/columns of A."
    endif



    !----------------------------------------------------------------------!
    ! Test getting a matrix row / column                                   !
    !----------------------------------------------------------------------!

    d1 = max(g1%get_max_degree(), g2%get_max_degree())
    allocate(nodes1(d1))

    d2 = max(h%get_max_degree(), ht%get_max_degree())
    allocate(nodes2(d2))

    d = max(g1%get_max_degree() + h%get_max_degree(), &
                & g2%get_max_degree() + ht%get_max_degree())
    allocate(nodes(d), slice(d))

    do k = 1, nn1
        d1 = g1%get_degree(k)
        call g1%get_neighbors(nodes1, k)

        d2 = h%get_degree(k)
        call h%get_neighbors(nodes2, k)

        d = d1 + d2
        call A%get_row(nodes, slice, k)

        if (.not. check_neighbors(d, d1, d2, &
                                & nodes, nodes1, nodes2 + nn1)) then
            print *, "Failed to get all non-zero entries in row", k
            call exit(1)
        endif


        call A%get_column(nodes, slice, k)

        if (.not. check_neighbors(d, d1, d2, &
                                & nodes, nodes1, nodes2 + nn1)) then
            print *, "Failed to get all non-zero entries in column", k
            call exit(1)
        endif
    enddo

    do k = 1, nn2
        d1 = g2%get_degree(k)
        call g2%get_neighbors(nodes1, k)

        d2 = ht%get_degree(k)
        call ht%get_neighbors(nodes2, k)

        d = d1 + d2
        call A%get_row(nodes, slice, k + nn1)

        if (.not. check_neighbors(d, d1, d2, &
                                & nodes, nodes1 + nn1, nodes2)) then
            print *, "Failed to get all non-zero entries in row", k + nn1
            call exit(1)
        endif


        call A%get_column(nodes, slice, k + nn1)

        if (.not. check_neighbors(d, d1, d2, &
                                & nodes, nodes1 + nn1, nodes)) then
            print *, "Failed to get all non-zero entries in column", k + nn1
            call exit(1)
        endif
    enddo

    deallocate(nodes, nodes1, nodes2, slice)

    if (verbose) then
        print *, "o Done checking row/column access."
    endif



    !----------------------------------------------------------------------!
    ! Test matrix-vector multiplication                                    !
    !----------------------------------------------------------------------!

    ! Compute the product of the composite matrix and and a random vector
    call A%matvec(x, y)

    ! Compute the product exactly from the underlying graphs
    d = g1%get_max_degree()
    allocate(nodes(d))
    do i = 1, nn1
        d = g1%get_degree(i)
        call g1%get_neighbors(nodes, i)

        do k = 1, d
            j = nodes(k)
            z(i) = z(i) + x(i) - x(j)
        enddo
    enddo

    deallocate(nodes)


    d = g2%get_max_degree()
    allocate(nodes(d))
    do i = 1, nn2
        d = g2%get_degree(i)
        call g2%get_neighbors(nodes, i)

        do k = 1, d
            j = nodes(k)
            z(i + nn1) = z(i + nn1) + x(i + nn1) - x(j + nn1)
        enddo
    enddo

    !----------------------------------------------------------------------!
    ! See how it was kind of annoying to keep track the offset `nn1`       !
    ! there? Imagine how much worse it would be if our composite matrix    !
    ! consisted of even more patches!                                      !
    ! The composite matrix type allows us to avoid having to remember all  !
    ! the offsets; the only reason they show up here is so that we can     !
    ! test that the matvec procedure is correct.                           !
    !----------------------------------------------------------------------!

    deallocate(nodes)


    d = h%get_max_degree()
    allocate(nodes(d))
    do i = 1, nn1
        d = h%get_degree(i)
        call h%get_neighbors(nodes, i)
        do k = 1, d
            j = nodes(k)
            z(i) = z(i) + x(i) - x(j + nn1)
        enddo
    enddo

    do j = 1, nn1
        d = h%get_degree(j)
        call h%get_neighbors(nodes, j)
        do k = 1, d
            i = nodes(k)
            z(i + nn1) = z(i + nn1) + x(i + nn1) - x(j)
        enddo
    enddo

    deallocate(nodes)


    ! Compute the RMS error
    mse = dsqrt( dot_product(y - z, y - z) / dot_product(x, x) )

    if (mse > 1.0e-14) then
        print *, "Matrix-vector multiplication failed."
        print *, "Error in compute matrix-vector product relative to"
        print *, "exact value:", mse
        call exit(1)
    endif

    if (verbose) then
        print *, "o Done checking matrix-vector multiplication."
    endif



    !----------------------------------------------------------------------!
    ! Test iterating over the matrix entries                               !
    !----------------------------------------------------------------------!
    y = 0.0_dp

    ! Manually compute a matrix-vector product `y = A * x` by iterating
    ! over all the matrix entries
    cursor = A%make_cursor()
    do while (.not. cursor%done())
        call A%get_entries(edges, vals, cursor, batch_size, num_returned)

        do k = 1, num_returned
            i = edges(1, k)
            j = edges(2, k)

            y(i) = y(i) + vals(k) * x(j)
        enddo
    enddo

    ! Compare the computed product `y` with the exact result `z`
    mse = dsqrt( dot_product(y - z, y - z) / dot_product(x, x) )

    if (mse > 1.0e-14) then
        print *, "Iterating over all matrix entries failed."
        call exit(1)
    endif

    if (verbose) then
        print *, "o Done checking matrix value iterator."
    endif



    ! Destroy any heap-allocated objects
    call A%destroy()
    call g1%destroy()
    call g2%destroy()
    call h%destroy()
    call ht%destroy()
    deallocate(g1, g2, h, ht)



! Auxiliary subroutines
contains


!--------------------------------------------------------------------------!
subroutine erdos_renyi_graph(g, m, n, p, symmetric)                        !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(graph_interface), intent(inout) :: g
    integer, intent(in) :: m, n
    real(dp), intent(in) :: p
    logical, intent(in), optional :: symmetric
    ! local variables
    integer :: i, j
    real(dp) :: q
    logical :: sym

    sym = .false.
    if (present(symmetric)) sym = symmetric

    call g%init(m, n)

    do i = 1, m
        if (sym) call g%add_edge(i, i)

        do j = i + 1, n
            call random_number(q)
            if (q < p) then
                call g%add_edge(i, j)
                if (sym) call g%add_edge(j, i)
            endif
        enddo
    enddo

end subroutine erdos_renyi_graph



!--------------------------------------------------------------------------!
subroutine erdos_renyi_matrix(A, g)                                        !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(sparse_matrix_interface), intent(inout) :: A
    class(graph_interface), intent(in) :: g
    ! local variables
    integer :: i, j, k, d
    integer, allocatable :: nodes(:)

    call A%init(g%m, g%n, g)

    d = g%get_max_degree()
    allocate(nodes(d))

    do i = 1, g%m
        d = g%get_degree(i)
        call g%get_neighbors(nodes, i)

        do k = 1, d
            j = nodes(k)

            call A%add(i, j, -1.0_dp)
            call A%add(i, i, +1.0_dp)
        enddo
    enddo

end subroutine erdos_renyi_matrix



!--------------------------------------------------------------------------!
subroutine wrong_matrix_entry_error(it, jt, i, j, correct_val, found_val)  !
!--------------------------------------------------------------------------!
    integer, intent(in) :: it, jt, i, j
    real(dp), intent(in) :: correct_val, found_val

    write(*, 10) i, j
10  format("Getting / setting entry (", i4, ", ", i4, ")")
    write(*, 20) it, jt
20  format(" of sub-matrix (", i4, ", ", i4, ") failed.")
    write(*, 30) correct_val
30  format("Correct value: ", f9.6)
    write(*, 40) found_Val
40  format("Value found  : ", f9.6)

    call exit(1)

end subroutine



!--------------------------------------------------------------------------!
function check_neighbors(d, d1, d2, nodes, nodes1, nodes2) result(correct) !
!--------------------------------------------------------------------------!
! Check to see if every element of the arrays `nodes1`, `nodes2` appears   !
! somewhere in the array `nodes`, and vice versa.                          !
!--------------------------------------------------------------------------!
    ! input/output variables
    integer, intent(in) :: d, d1, d2, nodes(:), nodes1(:), nodes2(:)
    logical :: correct
    ! local variables
    integer :: j, k

    correct = .true.

    do k = 1, d1
        j = nodes1(k)
        correct = correct .and. any(nodes(1:d) == j)
    enddo

    do k = 1, d2
        j = nodes2(k)
        correct = correct .and. any(nodes(1:d) == j)
    enddo

    do k = 1, d
        j = nodes(k)
        correct = correct .and. &
                    & (any(nodes1(1:d1) == j) .or. any(nodes2(1:d2) == j))
    enddo

end function check_neighbors



end program matrix_test_composite

