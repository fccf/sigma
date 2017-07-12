!--------------------------------------------------------------------------!
program matrix_test_strategy                                               !
!--------------------------------------------------------------------------!
!     This program tests using the type sparse_matrix as the container of  !
! a strategy. The abstract strategy is                                     !
!     sparse_matrix_interface                                              !
! and the concrete strategy is one of the sparse matrix storage formats,   !
! such as CSR or ellpack.                                                  !
!     Using this object allows the user to transparently change the        !
! storage format of a sparse matrix without having to explicitly change    !
! the dynamic type of the object. Instead, that occurs behind the scenes.  !
!--------------------------------------------------------------------------!

use sigma

implicit none

    ! graph used as the matrix substrate
    type(ll_graph) :: g

    ! sparse matrix objects
    type(sparse_matrix) :: A

    ! vectors
    real(dp), allocatable :: x(:), y(:), w(:)

    ! integer indices
    integer :: i, j, k, d, nn

    ! permutation
    integer, allocatable :: p(:)

    ! variables for getting matrix rows / columns
    integer :: row_degree, col_degree
    integer, allocatable :: nodes(:)
    real(dp), allocatable :: slice(:)

    ! random numbers
    real(dp) :: c, z

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



    !----------------------------------------------------------------------!
    ! Set the matrix size and initialize a random seed                     !
    !----------------------------------------------------------------------!
    nn = 256
    c = log(1.0_dp * nn) / log(2.0_dp) / nn

    call init_seed()



    !----------------------------------------------------------------------!
    ! Make a random reference graph                                        !
    !----------------------------------------------------------------------!
    call g%init(nn)

    do i = 1, nn
        call g%add_edge(i, i)

        do j = i + 1, nn
            call random_number(z)

            if (z < c) then
                call g%add_edge(i, j)
                call g%add_edge(j, i)
            endif
        enddo
    enddo

    d = g%get_max_degree()
    allocate(nodes(d), slice(d))

    if (verbose) then
        print *, "o Done generating Erdos-Renyi graph."
        print *, "    Number of vertices: ", nn
        print *, "    Number of edges:    ", g%get_num_edges()
        print *, "    Maximum degree:     ", d
    endif



    !----------------------------------------------------------------------!
    ! Create a matrix in CSR format to represent the Laplacian of `g`      !
    !----------------------------------------------------------------------!
    call A%set_matrix_type("csr")
    call A%set_dimensions(nn, nn)
    call A%copy_graph(g)
    call A%zero()

    do i = 1, nn
        d = g%get_degree(i)
        call g%get_neighbors(nodes, i)
        do k = 1, d
            j = nodes(k)
            call A%add_value(i, j, -1.0_dp)
            call A%add_value(i, i, +1.0_dp)
        enddo
    enddo

    if (verbose) then
        print *, "o Done creating graph Laplacian."
    endif



    !----------------------------------------------------------------------!
    ! Test all of the matrix operations for correctness                    !
    !----------------------------------------------------------------------!
    do i = 1, nn
        d = g%get_degree(i) - 1
        z = A%get_value(i, i)
        if (z /= d) then
            print *, "Setting or getting matrix entry failed."
            print *, "Degree of node", i, ":", d
            print *, "A(i, i) =", z
            call exit(1)
        endif

        do j = i + 1, nn
            z = A%get_value(i, j)
            if (g%connected(i, j)) then
                if (z /= -1) then
                    print *, "Setting or getting matrix entry failed."
                    print *, "Nodes", i, ",", j
                    print *, "are connected in g but A(i, j) =", z
                    call exit(1)
                endif
            else
                if (z /= 0) then
                    print *, "Setting or getting matrix entry failed."
                    print *, "Nodes", i, ",", j
                    print *, "are not connected in g but A(i, j) =", z
                    call exit(1)
                endif
            endif
        enddo
    enddo

    if (verbose) then
        print *, "o Getting / setting matrix entries works."
    endif


    do i = 1, nn
        d = g%get_degree(i)
        call A%get_row(nodes, slice, i)

        do k = 1, d
            j = nodes(k)
            if (j /= i) then
                if (slice(k) /= -1) then
                    print *, "Getting matrix row failed."
                    print *, "Entry ", i, j
                    print *, "should be -1; value found:", slice(k)
                    call exit(1)
                endif
            elseif (j == i) then
                if (slice(k) /= d - 1) then
                    print *, "Getting matrix row failed."
                    print *, "Entry ", i, i
                    print *, "should be", d - 1, "; value found:", slice(k)
                endif
            endif
        enddo
    enddo

    do j = 1, nn
        d = g%get_degree(j)
        call A%get_column(nodes, slice, j)

        do k = 1, d
            i = nodes(k)
            if (j /= i) then
                if (slice(k) /= -1) then
                    print *, "Getting matrix column failed."
                    print *, "Entry ", i, j
                    print *, "should be -1; value found:", slice(k)
                    call exit(1)
                endif
            elseif (j == i) then
                if (slice(k) /= d - 1) then
                    print *, "Getting matrix column failed."
                    print *, "Entry ", j, j
                    print *, "should be", d - 1, "; value found:", slice(k)
                endif
            endif
        enddo
    enddo

    if (verbose) then
        print *, "o Getting matrix row / column works."
    endif



    !----------------------------------------------------------------------!
    ! Test matrix-vector multiplication                                    !
    !----------------------------------------------------------------------!
    allocate( x(nn), y(nn), w(nn) )

    x = 0.0_dp
    y = 0.0_dp
    w = 0.0_dp

    ! Make a random vector x
    call random_number(x)

    ! Compute `y = L(g) * x` exactly
    do i = 1, nn
        d = g%get_degree(i)
        call g%get_neighbors(nodes, i)

        y(i) = d * x(i)

        do k = 1, d
            j = nodes(k)

            y(i) = y(i) - x(j)
        enddo
    enddo

    ! Compute the matrix-vector product using the composite matrx
    call A%matvec(x, w)

    ! Compare the two
    z = dsqrt( dot_product(y - w, y - w) / dot_product(x, x) )

    if (z > 1.0e-14) then
        print *, "Matrix-vector multiplication failed."
        print *, "Error in computing matrix-vector product relative to"
        print *, "exact value:", z
        call exit(1)
    endif

    if (verbose) then
        print *, "o Matrix-vector product works."
    endif



    call g%destroy()
    call A%destroy()

    deallocate(nodes)
    deallocate(slice)


end program matrix_test_strategy

