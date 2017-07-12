!--------------------------------------------------------------------------!
program matrix_test_basics                                                 !
!--------------------------------------------------------------------------!
! This program performs tests of basic matrix operations:                  !
!     o initialization                                                     !
!     o getting / setting entries                                          !
!     o iteration over entries                                             !
!     o matrix-vector multiplication                                       !
!     o storage compression                                                !
!     o permutation                                                        !
!--------------------------------------------------------------------------!

use sigma

implicit none

    ! graph used as the matrix substrate
    type(ll_graph) :: g

    ! sparse and dense matrices
    class(sparse_matrix_interface), pointer :: A
    real(dp), allocatable :: B(:,:), BP(:,:), AD(:,:)

    ! vectors
    real(dp), allocatable :: x(:), y1(:), y2(:)

    ! integer indices
    integer :: i, j, k, d, nn, frmt

    ! permutation
    integer, allocatable :: p(:)

    ! variables for getting matrix rows / columns
    integer :: row_degree, col_degree
    integer, allocatable :: nodes(:)
    real(dp), allocatable :: slice(:)

    ! random numbers
    real(dp) :: c, w, z

    ! command-line argument parsing
    character(len=16) :: arg
    logical :: verbose

    ! other junk
    logical :: correct



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

    nn = 64
    c = log(1.0_dp * nn) / log(2.0_dp) / nn

    call init_seed()



    !----------------------------------------------------------------------!
    ! Make a random reference sparse matrix, stored as a dense matrix      !
    !----------------------------------------------------------------------!

    allocate(B(nn, nn))
    allocate(x(nn), y1(nn), y2(nn))
    B = 0.0_dp

    do j = 1, nn
        do i = 1, nn
            call random_number(z)
            if (z < c) then
                call random_number(w)
                B(i, j) = w
            endif
        enddo
    enddo

    ! Compute the row degree of the graph
    row_degree = 0
    do i = 1, nn
        k = count(B(i, :) /= 0)

        ! Make sure that every row has at least one entry; ellpack_matrix
        ! fails otherwise
        if (k == 0) then
            call random_number(z)
            j = int(z * nn) + 1

            call random_number(w)
            B(i, j) = w

            k = 1
        endif

        row_degree = max(k, row_degree)
    enddo

    ! Compute the column degree of the graph
    col_degree = 0
    do j = 1, nn
        k = count(B(:, j) /= 0)

        if (k == 0) then
            call random_number(z)
            i = int(z * nn) + 1

            call random_number(w)
            B(i, j) = w

            k = 1
        endif

        col_degree = max(k, col_degree)
    enddo

    d = max(row_degree, col_degree)
    allocate( nodes(d), slice(d) )



    !----------------------------------------------------------------------!
    ! Make a random permutation and permute the reference matrix           !
    !----------------------------------------------------------------------!
    allocate(p(nn))
    do i = 1, nn
        p(i) = i
    enddo

    do i = nn, 2, -1
        ! Pick a random number `j` between 1 and `i`
        call random_number(z)
        j = int(z * i) + 1

        ! Swap `p(i)` and `p(j)`
        k = p(i)
        p(i) = p(j)
        p(j) = k
    enddo

    allocate(BP(nn, nn))



    !----------------------------------------------------------------------!
    ! Make a graph on the reference matrix                                 !
    !----------------------------------------------------------------------!

    call g%init(nn, nn)

    do j = 1, nn
        do i = 1, nn
            if (B(i, j) /= 0) call g%add_edge(i, j)
        enddo
    enddo

    allocate(AD(nn, nn))



    !----------------------------------------------------------------------!
    ! Test each matrix type                                                !
    !----------------------------------------------------------------------!
    do frmt = 1, num_matrix_types
        if (verbose) print *, 'Format #',frmt

        !-----------------------------------------
        ! Choose a type for `A` and initialize it
        call choose_matrix_type(A, frmt)
        call A%init(nn, nn, g)


        !--------
        ! Check that all the entries of `A` are zero
        do i = 1, nn
            do j = 1, nn
                z = A%get_value(i, j)
                if (z /= 0) then
                    print *, 'Entries of a just-initialized sparse matrix'
                    print *, 'should be zero! Terminating.'
                    call exit(1)
                endif
            enddo
        enddo


        !--------
        ! Set the entries of `A` to be the same as those of `B`
        do j = 1, nn
            do i = 1, nn
                z = B(i, j)
                if (z /= 0) call A%set_value(i, j, z)
            enddo
        enddo


        !--------
        ! Check that the entries of `A` are the same as those of `B`
        do j = 1, nn
            do i = 1, nn
                z = B(i, j)
                if (A%get_value(i, j) /= z) then
                    print *, 'Setting entry of A failed. Terminating.'
                    call exit(1)
                endif
            enddo
        enddo


        !--------
        ! Check that getting the number of non-zero entries of a matrix row
        ! or column works
        do i = 1, nn
            k = A%get_row_degree(i)
            if (k /= count(B(i, :) /= 0)) then
                print *, 'Failed to get degree of row', i
                print *, '# of non-zero entries in B:', count(B(i, :) /= 0)
                print *, '# of non-zero entries in A:', k
                print *, 'Terminating.'
                call exit(1)
            endif
        enddo

        do j = 1, nn
            k = A%get_column_degree(j)
            if (k /= count(B(:, j) /= 0)) then
                print *, 'Failed to get degree of column', j
                print *, '# of non-zero entries in B:', count(B(:, j) /= 0)
                print *, '# of non-zero entries in A:', k
                print *, 'Terminating.'
                call exit(1)
            endif
        enddo


        !--------
        ! Check that getting an entire row / column of the matrix works
        do i = 1, nn
            call A%get_row(nodes, slice, i)

            ! First, check that every entry returned from the sparse
            ! matrix `A` corresponds to the right value in the
            ! reference matrix `B`
            do k = 1, d
                j = nodes(k)
                if (j /= 0) then
                    if (slice(k) /= B(i, j)) then
                        print *, 'Getting row of sparse matrix failed.'
                        print *, 'Terminating.'
                        call exit(1)
                    endif
                endif
            enddo

            ! Next, check that every non-zero entry in row `i` of
            ! `B` was actually returned by `get_row`
            do j = 1, nn
                if (B(i, j) /= 0) then
                    correct = .false.
                    do k = 1, d
                        correct = correct .or. (nodes(k) == j)
                    enddo

                    if (.not. correct) then
                        print *, 'Getting row of sparse matrix failed, did'
                        print *, 'not return entry that is in the row.'
                        print *, 'Terminating.'
                    endif
                endif
            enddo
        enddo

        do j = 1, nn
            call A%get_column(nodes, slice, j)

            do k = 1, d
                i = nodes(k)
                if (i /= 0) then
                    if (slice(k) /= B(i, j)) then
                        print *, 'Getting column of sparse matrix failed.'
                        print *, 'Terminating.'
                        call exit(1)
                    endif
                endif
            enddo

            do i = 1, nn
                if (B(i, j) /= 0) then
                    correct = .false.
                    do k = 1, d
                        correct = correct .or. (nodes(k) == i)
                    enddo

                    if (.not. correct) then
                        print *, 'Getting col of sparse matrix failed, did'
                        print *, 'not return entry that is in the column.'
                        print *, 'Terminating.'
                        call exit(1)
                    endif
                endif
            enddo
        enddo


        !--------
        ! Check converting to a dense matrix
        call A%to_dense_matrix(AD)
        if (maxval(dabs(AD - B)) > 1.0e-15) then
            print *, 'Converting sparse to dense matrix yielded incorrect,'
            print *, 'result, likely a failure of matrix value iterator.'
            call exit(1)
        endif


        !--------
        ! Check matrix multiplication
        call random_number(x)
        y1 = 0.0_dp
        y2 = 0.0_dp

        call A%matvec(x, y1)
        y2 = matmul(B, x)

        w = maxval(dabs(y1-y2)) / maxval(dabs(y2))
        if (w > 1.0e-15) then
            print *, 'Matrix-vector multiplication failed.'
            print *, 'Error:', w
            print *, 'Terminating.'
            call exit(1)
        endif


        call random_number(x)
        y1 = 0.0_dp
        y2 = 0.0_dp

        call A%matvec_t(x, y1)
        y2 = matmul(transpose(B), x)

        w = maxval(dabs(y1-y2)) / maxval(dabs(y2))
        if (w > 1.0e-15) then
            print *, 'Matrix transpose-vector multiplication failed.'
            print *, 'Error:', w
            print *, 'Terminating.'
            call exit(1)
        endif


        !--------
        ! Check matrix permutation
        BP(:,p) = B(:,:)
        call A%right_permute(p)

        do j = 1, nn
            do i = 1, nn
                z = A%get_value(i, j)
                if (z /= BP(i, j)) then
                    print *, 'Right-permutation failed. Terminating.'
                    call exit(1)
                endif
            enddo
        enddo

        BP(p,:) = BP(:,:)
        call A%left_permute(p)

        do j = 1, nn
            do i = 1, nn
                z = A%get_value(i, j)
                if (z /= BP(i, j)) then
                    print *, 'Left-permutation failed. Terminating.'
                    call exit(1)
                endif
            enddo 
        enddo


        ! Destroy the matrix so it's ready for the next test
        call A%destroy()
        deallocate(A)
    enddo   ! End of loop over frmt


    call g%destroy()
    deallocate(p)
    deallocate(x, y1, y2)
    deallocate(B, BP)
    deallocate(nodes, slice)



end program matrix_test_basics

