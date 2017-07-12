module cs_graphs

use graph_interfaces
use util

implicit none



!--------------------------------------------------------------------------!
type, extends(graph_interface) :: cs_graph                                 !
!--------------------------------------------------------------------------!
    ! The array `node` stores the ending vertices of every edge in the
    ! graph, while the array `ptr` stores the starting index in `node` of
    ! neighbors of each vertex
    integer, allocatable :: ptr(:), node(:)

    ! Number of edges and maximum degree of all vertices of the graph
    integer :: ne, max_d
contains
    !--------------
    ! Constructors
    procedure :: init => cs_graph_init
    procedure :: build => cs_graph_build

    !-----------
    ! Accessors
    procedure :: get_num_edges => cs_get_num_edges
    procedure :: get_degree => cs_get_degree
    procedure :: get_max_degree => cs_get_max_degree
    procedure :: get_neighbors => cs_get_neighbors
    procedure :: connected => cs_connected
    procedure :: find_edge => cs_find_edge
    procedure, nopass :: is_get_neighbors_fast => get_neighbors_is_fast

    !---------------
    ! Edge iterator
    procedure :: make_cursor => cs_make_cursor
    procedure :: get_edges => cs_get_edges

    !----------
    ! Mutators
    procedure :: add_edge  => cs_add_edge
    procedure :: delete_edge => cs_delete_edge
    procedure :: left_permute => cs_graph_left_permute
    procedure :: right_permute => cs_graph_right_permute

    !-------------
    ! Destructors
    procedure :: destroy => cs_destroy

    !--------------------------
    ! Testing, debugging & I/O
    procedure :: dump_edges => cs_dump_edges

    !--------------------
    ! Auxiliary routines
    procedure, private :: prune_null_edges

end type cs_graph




contains




!==========================================================================!
!==== Constructors                                                     ====!
!==========================================================================!

!--------------------------------------------------------------------------!
subroutine cs_graph_init(g, n, m)                                          !
!--------------------------------------------------------------------------!
    class(cs_graph), intent(inout) :: g
    integer, intent(in) :: n
    integer, intent(in), optional :: m

    call g%add_reference()

    ! Set the number of (left-)nodes in the graph and allocate the node
    ! pointer array ptr
    g%n = n
    allocate( g%ptr(n+1) )
    g%ptr = 1

    ! If the graph is not square, set the number of right-nodes
    if (present(m)) then
        g%m = m
    else
        g%m = n
    endif

    ! Allocate the node array. If we're making an empty CS graph, that
    ! array has size 0.
    allocate( g%node(0) )

    ! Set the number of edges and max degree
    g%ne = 0
    g%max_d = 0

end subroutine cs_graph_init



!--------------------------------------------------------------------------!
subroutine cs_graph_build(g, n, m, get_edges, make_cursor, trans)          !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(cs_graph), intent(inout) :: g
    integer, intent(in) :: n, m
    procedure(get_edges_interface) :: get_edges
    procedure(make_cursor_interface) :: make_cursor
    logical, intent(in), optional :: trans
    ! local variables
    integer :: ord(2)
    integer :: i, j, k, l
    integer :: num_returned, edges(2, batch_size)
    type(graph_edge_cursor) :: cursor

    ord = [1, 2]
    if (present(trans)) then
        if (trans) ord = [2, 1]
    endif

    g%n = n
    g%m = m

    cursor = make_cursor()

    g%ne = cursor%last

    ! If the graph is already populated, clear it
    if (allocated(g%ptr)) deallocate(g%ptr)
    if (allocated(g%node)) deallocate(g%node)

    allocate(g%ptr(g%n + 1), g%node(g%ne))

    ! Fill the ptr array
    g%ptr = 0

    do while (.not. cursor%done())
        call get_edges(edges, cursor, batch_size, num_returned)

        do k = 1, num_returned
            i = edges(ord(1), k)
            g%ptr(i + 1) = g%ptr(i + 1) + 1
        enddo
    enddo

    g%ptr(1) = 1
    do i = 1, g%n
        g%ptr(i + 1) = g%ptr(i + 1) + g%ptr(i)
    enddo

    ! Iterate through all the edges again to fill the array `node`
    g%node = 0

    cursor = make_cursor()

    do while (.not. cursor%done())
        call get_edges(edges, cursor, batch_size, num_returned)

        do k = 1,num_returned
            i = edges(ord(1), k)
            j = edges(ord(2), k)

            !TODO try to make it more efficient
            do l = g%ptr(i), g%ptr(i + 1) - 1
                ! We need this provision for copying graphs whose iterators
                ! might return the same edge more than once
                if (g%node(l) == j) exit

                ! Otherwise, find a free spot to insert the next edge
                if (g%node(l) == 0) then
                    g%node(l) = j
                    exit
                endif
            enddo
        enddo
    enddo

    ! If we didn't fill up all the storage space of the graph, possibly
    ! because the graph we were copying had null edges, then rebuild the
    ! structure of `g` so it's at capacity.
    if (minval(g%node) == 0) then
        call g%prune_null_edges()
    endif

    g%max_d = 0
    do i = 1, g%n
        g%max_d = max(g%max_d, g%ptr(i + 1) - g%ptr(i))
    enddo

end subroutine cs_graph_build




!==========================================================================!
!==== Accessors                                                        ====!
!==========================================================================!

!--------------------------------------------------------------------------!
function cs_get_num_edges(g) result(k)                                     !
!--------------------------------------------------------------------------!
    class(cs_graph), intent(in) :: g
    integer :: k

    k = g%ne

end function cs_get_num_edges



!--------------------------------------------------------------------------!
function cs_get_degree(g, i) result(d)                                     !
!--------------------------------------------------------------------------!
    class(cs_graph), intent(in) :: g
    integer, intent(in) :: i
    integer :: d

    d = g%ptr(i + 1) - g%ptr(i)

end function cs_get_degree



!--------------------------------------------------------------------------!
function cs_get_max_degree(g) result(k)                                    !
!--------------------------------------------------------------------------!
    class(cs_graph), intent(in) :: g
    integer :: k

    k = g%max_d

end function cs_get_max_degree



!--------------------------------------------------------------------------!
subroutine cs_get_neighbors(g, neighbors, i)                               !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(cs_graph), intent(in) :: g
    integer, intent(out) :: neighbors(:)
    integer, intent(in) :: i
    ! local variables
    integer :: start, finish, degree

    degree = g%ptr(i+1) - g%ptr(i)
    start = g%ptr(i)
    finish = g%ptr(i + 1) - 1

    neighbors = 0
    neighbors(1 : degree) = g%node(start : finish)

end subroutine cs_get_neighbors



!--------------------------------------------------------------------------!
function cs_connected(g, i, j)                                             !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(cs_graph), intent(in) :: g
    integer, intent(in) :: i,j
    logical :: cs_connected
    ! local variables
    integer :: k

    cs_connected = .false.

    do k = g%ptr(i), g%ptr(i + 1) - 1
        if (g%node(k) == j) cs_connected = .true.
    enddo

end function cs_connected



!--------------------------------------------------------------------------!
function cs_find_edge(g, i, j)                                             !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(cs_graph), intent(in) :: g
    integer, intent(in) :: i, j
    integer :: cs_find_edge
    ! local variables
    integer :: k

    cs_find_edge = -1

    do k = g%ptr(i), g%ptr(i + 1) - 1
        if (g%node(k) == j) cs_find_edge = k
    enddo

end function cs_find_edge




!==========================================================================!
!==== Edge iterator                                                    ====!
!==========================================================================!

!--------------------------------------------------------------------------!
function cs_make_cursor(g) result(cursor)                                  !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(cs_graph), intent(in) :: g
    type(graph_edge_cursor) :: cursor
    ! local variables
    integer :: k

    cursor%first = 1
    cursor%last = g%ne
    cursor%current = 0

    k = 1
    do while(g%ptr(k + 1) - g%ptr(k) == 0)
        k = k + 1
    enddo

    cursor%edge(:) = [k, g%node(g%ptr(k))]

end function cs_make_cursor



!--------------------------------------------------------------------------!
subroutine cs_get_edges(g, edges, cursor, num_edges, num_returned)         !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(cs_graph), intent(in) :: g
    integer, intent(in) :: num_edges
    integer, intent(out) :: edges(2, num_edges)
    type(graph_edge_cursor), intent(inout) :: cursor
    integer, intent(out) :: num_returned
    ! local variables
    integer :: i, k, num, bt

    associate(current => cursor%current)

    ! Set up the returned edges to be 0
    edges = 0

    ! Count how many edges we're actually going to return; we'll either
    ! return how many edges the user asked for, or, if that amount would
    ! go beyond the final edge that the cursor is allowed to access, all
    ! of the remaining edges
    num_returned = min(num_edges, cursor%last - current)

    ! Fill the edges array's second row with the edge endpoints
    edges(2, 1 : num_returned) = g%node(current+1 : current+num_returned)

    ! Find the last vertex that the edge iterator left off at
    i = cursor%edge(1)

    ! Total number of edges from the current batch that we've fetched so far
    k = 0

    ! Keep fetching more edges as long as we haven't got the whole batch
    do while(k < num_returned)
        ! Number of edges we'll return that neighbor vertex `i`
        ! Either it's all the neighbors of `i`, or however many neighbors
        ! are left to be returned from the current batch if `i` has more
        ! more neighbors than that
        num = min(g%ptr(i + 1) - 1 - current, num_returned - k)

        edges(1, k+1 : k+num) = i

        ! This is a spot of bit-shifting magic in order to avoid the
        ! conditional expression
        !     if (num == g%ptr(i + 1) - 1 - current) i = i + 1
        ! The two are equivalent.
        bt = (sign(1, num - (g%ptr(i+1) - 1 - current)) + 1) / 2
        i = i + bt

        current = current + num
        k = k + num
    enddo

    cursor%edge(1) = i

    end associate

end subroutine cs_get_edges




!==========================================================================!
!==== Mutators                                                         ====!
!==========================================================================!

!--------------------------------------------------------------------------!
subroutine cs_add_edge(g, i, j)                                            !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(cs_graph), intent(inout) :: g
    integer, intent(in) :: i, j
    ! local variables
    integer :: k, indx, d
    integer, allocatable :: node(:)

    if (.not. g%connected(i, j)) then
        ! Make a temporary array
        allocate(node(g%ne + 1))
        node = 0

        ! Store the location within the temporary array where the new edge
        ! will go
        indx = g%ptr(i + 1)

        ! Copy all the old data into the temporary array
        node(1 : indx - 1) = g%node(1 : indx - 1)
        node(indx + 1 : g%ne + 1) = g%node(indx : g%ne)

        ! Put the new edge into the temporary array
        node(indx) = j

        ! Transfer the allocation status from the temporary array to `g`
        call move_alloc(from = node, to = g%node)

        ! Update the `ptr` array to reflect the new connectivity structure
        ! of `g`
        do k = i + 1, g%n + 1
            g%ptr(k) = g%ptr(k) + 1
        enddo

        ! Increment the number of edges of `g`
        g%ne = g%ne + 1

        ! Increment the max degree of `g` if need be
        d = g%ptr(i + 1) - g%ptr(i)
        g%max_d = max(g%max_d, d)
    endif

end subroutine cs_add_edge



!--------------------------------------------------------------------------!
subroutine cs_delete_edge(g, i, j)                                         !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(cs_graph), intent(inout) :: g
    integer, intent(in) :: i, j
    ! local variables
    integer :: k, indx, d
    integer, allocatable :: node(:)

    ! Find the index in the list of edges of the edge to be removed
    indx = g%find_edge(i, j)

    ! If there was no such edge in the first place, do nothing
    if (indx /= -1) then
        ! Record the degree of the starting vertex of the edge that is to
        ! be deleted
        d = g%ptr(i + 1) - g%ptr(i)

        ! Make a temporary array
        allocate(node(g%ne - 1))

        ! Copy all the old data into the temporary array
        node(1    : indx - 1) = g%node(1        : indx - 1)
        node(indx : g%ne - 1) = g%node(indx + 1 : g%ne    )

        ! Transfer the allocation status from the temporary array to `g`
        call move_alloc(from = node, to = g%node)

        ! Update the `ptr` array
        do k = i + 1, g%n + 1
            g%ptr(k) = g%ptr(k) - 1
        enddo

        ! Decrement the number of edges of `g`
        g%ne = g%ne - 1

        ! If the vertex `i` was of maximal degree, it's possible that the
        ! max degree of all the graph's vertices has decreased.
        if (d == g%max_d) then
            do k = 1, g%n
                d = g%ptr(k + 1) - g%ptr(k)
                g%max_d = max(g%max_d, d)
            enddo
        endif

    endif

end subroutine cs_delete_edge



!--------------------------------------------------------------------------!
subroutine cs_graph_left_permute(g, p, edge_p)                             !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(cs_graph), intent(inout) :: g
    integer, intent(in) :: p(:)
    integer, allocatable, intent(out), optional :: edge_p(:,:)
    ! local variables
    integer :: i, k, d, ptr(g%n + 1), node(g%ne)

    ! If the user has asked to see the edge permutation, fill the
    ! first and last constituent arrays
    if (present(edge_p)) then
        allocate(edge_p(3, g%n))
        do i = 1, g%n
            edge_p(1, i) = g%ptr(i)
            edge_p(3, i) = g%ptr(i + 1) - g%ptr(i)
        enddo
    endif

    ! Find the number of edges for each node under the new ordering
    do i = 1, g%n
        ptr(p(i) + 1) = g%ptr(i + 1) - g%ptr(i)
    enddo

    ! Knowing how many edges each node has in the new ordering, we can
    ! prepare the ptr array
    ptr(1) = 1
    do i = 1, g%n
        ptr(i + 1) = ptr(i + 1) + ptr(i)
    enddo

    ! Shuffle the node array
    do i = 1, g%n
        d = g%ptr(i + 1) - g%ptr(i)
        do k = 0, d - 1
            node( ptr(p(i)) + k ) = g%node( g%ptr(i) + k )
        enddo
    enddo

    ! Replace g's versions of ptr and node with the reordered versions
    g%ptr = ptr
    g%node = node

    ! If the user has asked to see the edge permutation, fill the second
    ! constituent array
    if (present(edge_p)) then
        do i = 1, g%n
            edge_p(2, i) = g%ptr(p(i))
        enddo
    endif

end subroutine cs_graph_left_permute



!--------------------------------------------------------------------------!
subroutine cs_graph_right_permute(g, p, edge_p)                            !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(cs_graph), intent(inout) :: g
    integer, intent(in) :: p(:)
    integer, allocatable, intent(out), optional :: edge_p(:,:)
    ! local variables
    integer :: j, k

    do k=1, g%ne
        j = g%node(k)
        g%node(k) = p(j)
    enddo

    if (present(edge_p)) allocate(edge_p(0,0))

end subroutine cs_graph_right_permute




!==========================================================================!
!==== Destructors                                                      ====!
!==========================================================================!

!--------------------------------------------------------------------------!
subroutine cs_destroy(g)                                                   !
!--------------------------------------------------------------------------!
    class(cs_graph), intent(inout) :: g

    deallocate(g%ptr, g%node)
    g%n = 0
    g%m = 0
    g%ne = 0
    g%max_d = 0
    g%reference_count = 0

end subroutine cs_destroy




!==========================================================================!
!==== Testing, debugging & I/O                                         ====!
!==========================================================================!

!--------------------------------------------------------------------------!
subroutine cs_dump_edges(g, edges)                                         !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(cs_graph), intent(in) :: g
    integer, intent(out) :: edges(:,:)
    ! local variables
    integer :: i, k

    do i = 1, g%n
        do k = g%ptr(i), g%ptr(i + 1) - 1
            edges(1, k) = i
            edges(2, k) = g%node(k)
        enddo
    enddo

end subroutine cs_dump_edges




!==========================================================================!
!==== Auxiliary routines                                               ====!
!==========================================================================!

!--------------------------------------------------------------------------!
subroutine prune_null_edges(g)                                             !
!--------------------------------------------------------------------------!
    ! input/output variables
    class(cs_graph), intent(inout) :: g
    ! local variables
    integer :: i, j, k, next, ne
    integer, allocatable :: ptr(:), node(:)

    ne = count(g%node /= 0)

    if (ne < size(g%node)) then
        g%ne = ne

        allocate(node(ne), ptr(g%n + 1))
        ptr = 0
        node = 0
        ptr(1) = 1

        g%max_d = 0
        next = 1

        do i = 1, g%n
            do k = g%ptr(i), g%ptr(i + 1) - 1
                j = g%node(k)
                if (j /= 0) then
                    node(next) = j
                    next = next + 1
                endif
            enddo

            ptr(i + 1) = next

            g%max_d = max(g%max_d, g%ptr(i + 1) - g%ptr(i))
        enddo

        call move_alloc(from = node, to = g%node)
        call move_alloc(from = ptr,  to = g%ptr )
    endif

end subroutine prune_null_edges


end module cs_graphs
