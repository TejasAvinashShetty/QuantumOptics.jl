module stochastic_semiclassical

export schroedinger_semiclassical, master_semiclassical

using ...bases, ...states, ...operators
using ...operators_dense, ...operators_sparse
using ...semiclassical
import ...semiclassical: recast!, State, dmaster_h_dynamic
using ...timeevolution
import ...timeevolution: integrate_stoch
import ...timeevolution.timeevolution_schroedinger: dschroedinger, dschroedinger_dynamic
using ...stochastic
import ...stochastic.stochastic_master: dneumann, dwiseman, dwiseman_nl, dlindblad

const DecayRates = Union{Vector{Float64}, Matrix{Float64}, Void}
const DiffArray = Union{Vector{Complex128}, Array{Complex128, 2}}

"""
    semiclassical.schroedinger_stochastic(tspan, state0, fquantum, fclassical[; fout, ...])

Integrate time-dependent Schrödinger equation coupled to a classical system.

# Arguments
* `tspan`: Vector specifying the points of time for which the output should
        be displayed.
* `state0`: Initial semi-classical state [`semiclassical.State`](@ref).
* `fquantum`: Function `f(t, psi, u) -> H` returning the time and or state
        dependent Hamiltonian.
* `fclassical`: Function `f(t, psi, u, du)` calculating the possibly time and
        state dependent derivative of the classical equations and storing it
        in the vector `du`.
* `fstoch_quantum=nothing`: Function `f(t, psi, u) -> Hs` that returns a vector
        of operators corresponding to the stochastic terms of the Hamiltonian.
        NOTE: Either this function or `fstoch_classical` has to be defined.
* `fstoch_classical=nothing`: Function `f(t, psi, u, du)` that calculates the
        stochastic terms of the derivative `du`.
        NOTE: Either this function or `fstoch_quantum` has to be defined.
* `fout=nothing`: If given, this function `fout(t, state)` is called every time
        an output should be displayed. ATTENTION: The given state is neither
        normalized nor permanent!
* `noise_processes=0`: Number of distinct quantum noise processes in the equation.
        This number has to be equal to the total number of noise operators
        returned by `fstoch`. If unset, the number is calculated automatically
        from the function output.
        NOTE: Set this number if you want to avoid an initial calculation of
        the function output!
* `noise_prototype_classical=nothing`: The equivalent of the optional argument
        `noise_rate_prototype` in `StochasticDiffEq` for the classical
        stochastic function `fstoch_classical` only. Must be set for
        non-diagonal classical noise or combinations of quantum and classical
        noise. See the documentation for details.
* `kwargs...`: Further arguments are passed on to the ode solver.
"""
function schroedinger_semiclassical(tspan, state0::State{Ket}, fquantum::Function,
                fclassical::Function; fstoch_quantum::Union{Void, Function}=nothing,
                fstoch_classical::Union{Void, Function}=nothing,
                fout::Union{Function,Void}=nothing,
                noise_processes::Int=0,
                noise_prototype_classical=nothing,
                kwargs...)
    tspan_ = convert(Vector{Float64}, tspan)
    dschroedinger_det(t::Float64, state::State{Ket}, dstate::State{Ket}) = semiclassical.dschroedinger_dynamic(t, state, fquantum, fclassical, dstate)

    if isa(fstoch_quantum, Void) && isa(fstoch_classical, Void)
        throw(ArgumentError("No stochastic functions provided!"))
    end

    x0 = Vector{Complex128}(length(state0))
    recast!(state0, x0)
    state = copy(state0)
    dstate = copy(state0)

    if noise_processes == 0
        n = 0
        if isa(fstoch_quantum, Function)
            fs_out = fstoch_quantum(0.0, state0.quantum, state0.classical)
            n += length(fs_out)
        end
    else
        n = noise_processes
    end

    if n > 0 && isa(fstoch_classical, Function)
        if isa(noise_prototype_classical, Void)
            throw(ArgumentError("noise_prototype_classical must be set for combinations of quantum and classical noise!"))
        end
    end

    dschroedinger_stoch(dx::DiffArray,
            t::Float64, state::State{Ket}, dstate::State{Ket}, n::Int) =
            dschroedinger_stochastic(dx, t, state, fstoch_quantum, fstoch_classical, dstate, n)
    integrate_stoch(tspan_, dschroedinger_det, dschroedinger_stoch, x0, state, dstate, fout, n;
                    noise_prototype_classical = noise_prototype_classical,
                    kwargs...)
end

"""
    stochastic.master_semiclassical(tspan, rho0, H, Hs, J; <keyword arguments>)

Time-evolution according to a stochastic master equation.

For dense arguments the `master` function calculates the
non-hermitian Hamiltonian and then calls master_nh which is slightly faster.

# Arguments
* `tspan`: Vector specifying the points of time for which output should
        be displayed.
* `rho0`: Initial density operator. Can also be a state vector which is
        automatically converted into a density operator.
* `fquantum`: Function `f(t, rho, u) -> (H, J, Jdagger)` or
        `f(t, rho, u) -> (H, J, Jdagger, rates)` giving the deterministic
        part of the master equation.
* `fclassical`: Function `f(t, rho, u, du)` that calculates the classical
        derivatives `du`.
* `fstoch_quantum=nothing`: Function `f(t, rho, u) -> Js, Jsdagger` or
        `f(t, psi, u) -> Js, Jsdagger, rates_s` that returns the stochastic
        operator for the superoperator of the form `Js[i]*rho + rho*Jsdagger[i]`.
* `fstoch_classical=nothing`: Function `f(t, rho, u, du)` that calculates the
        stochastic terms of the derivative `du`.
* `fstoch_H=nothing`: Function `f(t, rho, u) -> Hs` providing a vector of operators
        that correspond to stochastic terms of the Hamiltonian.
* `fstoch_J=nothing`: Function `f(t, rho, u) -> (J, Jdagger)` or
        `f(t, rho, u) -> (J, Jdagger, rates)` giving a stochastic
        Lindblad term.
* `rates=nothing`: Vector or matrix specifying the coefficients (decay rates)
        for the jump operators. If nothing is specified all rates are assumed
        to be 1.
* `rates_s=nothing`: Vector or matrix specifying the coefficients (decay rates)
        for the stochastic jump operators. If nothing is specified all rates are assumed
        to be 1.
* `fout=nothing`: If given, this function `fout(t, rho)` is called every time
        an output should be displayed. ATTENTION: The given state rho is not
        permanent! It is still in use by the ode solver and therefore must not
        be changed.
* `noise_processes=0`: Number of distinct quantum noise processes in the equation.
        This number has to be equal to the total number of noise operators
        returned by `fstoch`. If unset, the number is calculated automatically
        from the function output.
        NOTE: Set this number if you want to avoid an initial calculation of
        the function output!
* `noise_prototype_classical=nothing`: The equivalent of the optional argument
        `noise_rate_prototype` in `StochasticDiffEq` for the classical
        stochastic function `fstoch_classical` only. Must be set for
        non-diagonal classical noise or combinations of quantum and classical
        noise. See the documentation for details.
* `nonlinear=true`: Specify whether or not to include the nonlinear term
        `expect(Js[i] + Jsdagger[i],rho)*rho` in the equation. This ensures
        that the trace of `rho` is conserved.
* `kwargs...`: Further arguments are passed on to the ode solver.
"""
function master_semiclassical(tspan::Vector{Float64}, rho0::State{DenseOperator},
                fquantum::Function, fclassical::Function;
                fstoch_quantum::Union{Function, Void}=nothing,
                fstoch_classical::Union{Function, Void}=nothing,
                fstoch_H::Union{Function, Void}=nothing, fstoch_J::Union{Function, Void}=nothing,
                rates::DecayRates=nothing, rates_s::DecayRates=nothing,
                fout::Union{Function,Void}=nothing,
                noise_processes::Int=0,
                noise_prototype_classical=nothing,
                nonlinear::Bool=true,
                kwargs...)

    tmp = copy(rho0.quantum)

    if isa(rates_s, Matrix{Float64})
        throw(ArgumentError("A matrix of stochastic rates is ambiguous! Please provide a vector of stochastic rates.
        You may want to set them as ones or use diagonaljumps."))
    end
    if isa(fstoch_quantum, Void) && isa(fstoch_classical, Void) && isa(fstoch_H, Void) && isa(fstoch_J, Void)
        throw(ArgumentError("No stochastic functions provided!"))
    end

    if noise_processes == 0
        n = 0
        if isa(fstoch_quantum, Function)
            fq_out = fstoch_quantum(0, rho0.quantum, rho0.classical)
            n += length(fq_out[1])
        end
        if isa(fstoch_H, Function)
            n += length(fstoch_H(0, rho0.quantum, rho0.classical))
        end
        if isa(fstoch_J, Function)
            n += length(fstoch_J(0, rho0.quantum, rho0.classical)[1])
        end
    else
        n = noise_processes
    end

    if n > 0 && isa(fstoch_classical, Function)
        if isa(noise_prototype_classical, Void)
            throw(ArgumentError("noise_prototype_classical must be set for combinations of quantum and classical noise!"))
        end
    end

    dmaster_determ(t::Float64, rho::State{DenseOperator}, drho::State{DenseOperator}) =
            dmaster_h_dynamic(t, rho, fquantum, fclassical, rates, drho, tmp)
    if isa(fstoch_H, Void) && isa(fstoch_J, Void)
        if nonlinear
            dmaster_stoch_std_nl(dx::DiffArray, t::Float64, rho::State{DenseOperator},
                            drho::State{DenseOperator}, n::Int) =
                dmaster_stoch_dynamic_nl(dx, t, rho, fstoch_quantum, fstoch_classical,
                            rates_s, drho, n)

            integrate_master_stoch(tspan, dmaster_determ, dmaster_stoch_std_nl,
                        rho0, fout, n;
                        noise_prototype_classical=noise_prototype_classical,
                        kwargs...)
        else
            dmaster_stoch_std(dx::DiffArray, t::Float64, rho::State{DenseOperator},
                            drho::State{DenseOperator}, n::Int) =
                dmaster_stoch_dynamic(dx, t, rho, fstoch_quantum, fstoch_classical,
                            rates_s, drho, n)

            integrate_master_stoch(tspan, dmaster_determ, dmaster_stoch_std, rho0, fout, n;
                        noise_prototype_classical=noise_prototype_classical,
                        kwargs...)
        end
    else
        if nonlinear
            dmaster_stoch_gen_nl(dx::DiffArray, t::Float64, rho::State{DenseOperator},
                            drho::State{DenseOperator}, n::Int) =
                dmaster_stoch_dynamic_general_nl(dx, t, rho, fstoch_quantum,
                            fstoch_classical, fstoch_H, fstoch_J, rates, rates_s,
                            drho, tmp, n)

            integrate_master_stoch(tspan, dmaster_determ, dmaster_stoch_gen_nl, rho0, fout, n;
                        noise_prototype_classical=noise_prototype_classical,
                        kwargs...)
        else
            dmaster_stoch_gen(dx::DiffArray, t::Float64, rho::State{DenseOperator},
                            drho::State{DenseOperator}, n::Int) =
                dmaster_stoch_dynamic_general(dx, t, rho, fstoch_quantum,
                            fstoch_classical, fstoch_H, fstoch_J, rates, rates_s,
                            drho, tmp, n)

            integrate_master_stoch(tspan, dmaster_determ, dmaster_stoch_gen, rho0, fout, n;
                        noise_prototype_classical=noise_prototype_classical,
                        kwargs...)
        end
    end
end
master_semiclassical(tspan::Vector{Float64}, psi0::State{Ket}, args...; kwargs...) =
        master_semiclassical(tspan, dm(psi0), args...; kwargs...)

# TODO: remove unnecessary recast!(dstate, dx) instances

function dschroedinger_stochastic(dx::Vector{Complex128}, t::Float64,
        state::State{Ket}, fstoch_quantum::Function, fstoch_classical::Void,
        dstate::State{Ket}, ::Int)
    H = fstoch_quantum(t, state.quantum, state.classical)
    recast!(dx, dstate)
    dschroedinger(state.quantum, H[1], dstate.quantum)
    recast!(dstate, dx)
end
function dschroedinger_stochastic(dx::Array{Complex128, 2},
        t::Float64, state::State{Ket}, fstoch_quantum::Function,
        fstoch_classical::Void, dstate::State{Ket}, n::Int)
    H = fstoch_quantum(t, state.quantum, state.classical)
    for i=1:n
        dx_i = @view dx[:, i]
        recast!(dx_i, dstate)
        dschroedinger(state.quantum, H[i], dstate.quantum)
        recast!(dstate, dx_i)
    end
end
function dschroedinger_stochastic(dx::DiffArray, t::Float64,
            state::State{Ket}, fstoch_quantum::Void, fstoch_classical::Function,
            dstate::State{Ket}, ::Int)
    dclassical = @view dx[length(state.quantum)+1:end, :]
    fstoch_classical(t, state.quantum, state.classical, dclassical)
end
function dschroedinger_stochastic(dx::Array{Complex128, 2}, t::Float64, state::State{Ket}, fstoch_quantum::Function,
            fstoch_classical::Function, dstate::State{Ket}, n::Int)
    dschroedinger_stochastic(dx, t, state, fstoch_quantum, nothing, dstate, n)

    dx_i = @view dx[length(state.quantum)+1:end, n+1:end]
    fstoch_classical(t, state.quantum, state.classical, dx_i)
end

function dmaster_stoch_dynamic(dx::Vector{Complex128}, t::Float64,
            state::State{DenseOperator}, fstoch_quantum::Function,
            fstoch_classical::Void,
            rates_s::DecayRates, dstate::State{DenseOperator}, ::Int)
    result = fstoch_quantum(t, state.quantum, state.classical)
    @assert 2 <= length(result) <= 3
    if length(result) == 2
        Js, Jsdagger = result
        rates_s_ = rates_s
    else
        Js, Jsdagger, rates_s_ = result
    end
    recast!(dx, dstate)
    dwiseman(state.quantum, rates_s_, Js, Jsdagger, dstate.quantum, 1)
    recast!(dstate, dx)
end
function dmaster_stoch_dynamic(dx::Array{Complex128, 2}, t::Float64,
            state::State{DenseOperator}, fstoch_quantum::Function,
            fstoch_classical::Void,
            rates_s::DecayRates, dstate::State{DenseOperator}, n::Int)
    result = fstoch_quantum(t, state.quantum, state.classical)
    @assert 2 <= length(result) <= 3
    if length(result) == 2
        Js, Jsdagger = result
        rates_s_ = rates_s
    else
        Js, Jsdagger, rates_s_ = result
    end
    for i=1:n
        dx_i = @view dx[:, i]
        recast!(dx_i, dstate)
        dwiseman(state.quantum, rates_s_, Js, Jsdagger, dstate.quantum, i)
        recast!(dstate, dx_i)
    end
end
function dmaster_stoch_dynamic(dx::DiffArray, t::Float64,
            state::State{DenseOperator}, fstoch_quantum::Void,
            fstoch_classical::Function,
            rates_s::DecayRates, dstate::State{DenseOperator}, ::Int)
    dclassical = @view dx[length(state.quantum)+1:end, :]
    fstoch_classical(t, state.quantum, state.classical, dclassical)
end
function dmaster_stoch_dynamic(dx::Array{Complex128, 2}, t::Float64,
            state::State{DenseOperator}, fstoch_quantum::Function,
            fstoch_classical::Function,
            rates_s::DecayRates, dstate::State{DenseOperator}, n::Int)
    dmaster_stoch_dynamic(dx, t, state, fstoch_quantum, nothing, rates_s, dstate, n)

    dx_i = @view dx[length(state.quantum)+1:end, n+1:end]
    fstoch_classical(t, state.quantum, state.classical, dx_i)
end
dmaster_stoch_dynamic(dx::DiffArray, t::Float64, state::State{DenseOperator}, ::Void, ::Void, args...) = nothing

function dmaster_stoch_dynamic_nl(dx::Vector{Complex128}, t::Float64,
            state::State{DenseOperator}, fstoch_quantum::Function,
            fstoch_classical::Void,
            rates_s::DecayRates, dstate::State{DenseOperator}, ::Int)
    result = fstoch_quantum(t, state.quantum, state.classical)
    @assert 2 <= length(result) <= 3
    if length(result) == 2
        Js, Jsdagger = result
        rates_s_ = rates_s
    else
        Js, Jsdagger, rates_s_ = result
    end
    recast!(dx, dstate)
    dwiseman_nl(state.quantum, rates_s_, Js, Jsdagger, dstate.quantum, 1)
    recast!(dstate, dx)
end
function dmaster_stoch_dynamic_nl(dx::Array{Complex128, 2}, t::Float64,
            state::State{DenseOperator}, fstoch_quantum::Function,
            fstoch_classical::Void,
            rates_s::DecayRates, dstate::State{DenseOperator}, n::Int)
    result = fstoch_quantum(t, state.quantum, state.classical)
    @assert 2 <= length(result) <= 3
    if length(result) == 2
        Js, Jsdagger = result
        rates_s_ = rates_s
    else
        Js, Jsdagger, rates_s_ = result
    end
    for i=1:n
        dx_i = @view dx[:, i]
        recast!(dx_i, dstate)
        dwiseman_nl(state.quantum, rates_s_, Js, Jsdagger, dstate.quantum, i)
        recast!(dstate, dx_i)
    end
end
function dmaster_stoch_dynamic_nl(dx::DiffArray,
            t::Float64, state::State{DenseOperator}, fstoch_quantum::Void,
            fstoch_classical::Function, rates_s::DecayRates, dstate::State{DenseOperator}, n::Int)
    dmaster_stoch_dynamic(dx, t, state, fstoch_quantum, fstoch_classical, rates_s, dstate, n)
end
function dmaster_stoch_dynamic_nl(dx::Array{Complex128, 2}, t::Float64,
            state::State{DenseOperator}, fstoch_quantum::Function,
            fstoch_classical::Function,
            rates_s::DecayRates, dstate::State{DenseOperator}, n::Int)
    dmaster_stoch_dynamic_nl(dx, t, state, fstoch_quantum, nothing, rates_s, dstate, n)

    dx_i = @view dx[length(state.quantum)+1:end, n+1:end]
    fstoch_classical(t, state.quantum, state.classical, dx_i)
end
dmaster_stoch_dynamic_nl(dx::DiffArray, t::Float64, state::State{DenseOperator}, ::Void, ::Void, args...) = nothing


function dmaster_stoch_dynamic_general(dx::Vector{Complex128}, t::Float64, state::State{DenseOperator},
            fstoch_quantum::Void, fstoch_classical::Void,
            fstoch_H::Function, fstoch_J::Void, rates::DecayRates, rates_s::DecayRates,
            dstate::State{DenseOperator}, tmp::DenseOperator, ::Int)
    H = fstoch_H(t, state.quantum, state.classical)
    recast!(dx, dstate)
    dneumann(state.quantum, H[1], dstate.quantum)
    recast!(dstate, dx)
end
function dmaster_stoch_dynamic_general(dx::Array{Complex128, 2}, t::Float64, state::State{DenseOperator},
            fstoch_quantum::Union{Function, Void}, fstoch_classical::Union{Function, Void},
            fstoch_H::Function, fstoch_J::Void, rates::DecayRates, rates_s::DecayRates,
            dstate::State{DenseOperator}, tmp::DenseOperator, n::Int)
    H = fstoch_H(t, state.quantum, state.classical)
    m = length(H)
    for i=n-m+1:n
        dx_i = @view dx[:, i]
        recast!(dx_i, dstate)
        dneumann(state.quantum, H[i-n+m], dstate.quantum)
    end
    dmaster_stoch_dynamic(dx, t, state, fstoch_quantum, fstoch_classical,
            rates_s, dstate, n-m)
end
function dmaster_stoch_dynamic_general(dx::Vector{Complex128}, t::Float64, state::State{DenseOperator},
            fstoch_quantum::Void, fstoch_classical::Void,
            fstoch_H::Void, fstoch_J::Function, rates::DecayRates, rates_s::DecayRates,
            dstate::State{DenseOperator}, tmp::DenseOperator, ::Int)
    result_J = fstoch_J(t, state.quantum, state.classical)

    @assert 2 <= length(result_J) <= 3
    if length(result_J) == 2
        J, Jdagger = result_J
        rates_ = rates
    else
        J, Jdagger, rates_ = result_J
    end
    recast!(dx, dstate)
    dlindblad(state.quantum, rates_, J, Jdagger, dstate.quantum, tmp, 1)
    recast!(dstate, dx)
end
function dmaster_stoch_dynamic_general(dx::Array{Complex128, 2}, t::Float64, state::State{DenseOperator},
            fstoch_quantum::Union{Function, Void}, fstoch_classical::Union{Function, Void},
            fstoch_H::Void, fstoch_J::Function, rates::DecayRates, rates_s::DecayRates,
            dstate::State{DenseOperator}, tmp::DenseOperator, n::Int)
    result_J = fstoch_J(t, state.quantum, state.classical)
    @assert 2 <= length(result_J) <= 3
    if length(result_J) == 2
        J, Jdagger = result_J
        rates_ = rates
    else
        J, Jdagger, rates_ = result_J
    end
    l = length(J)

    for i=n-l+1:n
        dx_i = @view dx[:, i]
        recast!(dx_i, dstate)
        dlindblad(state.quantum, rates_, J, Jdagger, dstate.quantum, tmp, i-n+l)
        recast!(dstate, dx_i)
    end
    dmaster_stoch_dynamic(dx, t, state, fstoch_quantum, fstoch_classical,
            rates_s, dstate, n-l)
end
function dmaster_stoch_dynamic_general(dx::Array{Complex128, 2}, t::Float64,
            state::State{DenseOperator}, fstoch_quantum::Union{Function, Void},
            fstoch_classical::Union{Function, Void},
            fstoch_H::Function, fstoch_J::Function, rates::DecayRates, rates_s::DecayRates,
            dstate::State{DenseOperator}, tmp::DenseOperator, n::Int)
    H = fstoch_H(t, state.quantum, state.classical)
    m = length(H)

    for i=n-m+1:n
        dx_i = @view dx[:, i]
        recast!(dx_i, dstate)
        dneumann(state.quantum, H[i-n+m], dstate.quantum)
        recast!(dstate, dx_i)
    end
    dmaster_stoch_dynamic_general(dx, t, state, fstoch_quantum, fstoch_classical,
            nothing, fstoch_J, rates, rates_s, dstate, tmp, n-m)
end

dmaster_stoch_dynamic_general_nl(dx::Vector{Complex128}, args...; kwargs...) =
    dmaster_stoch_dynamic_general(dx, args...; kwargs...)
function dmaster_stoch_dynamic_general_nl(dx::Array{Complex128, 2}, t::Float64, state::State{DenseOperator},
            fstoch_quantum::Union{Function, Void}, fstoch_classical::Union{Function, Void},
            fstoch_H::Function, fstoch_J::Void, rates::DecayRates, rates_s::DecayRates,
            dstate::State{DenseOperator}, tmp::DenseOperator, n::Int)
    H = fstoch_H(t, state.quantum, state.classical)
    m = length(H)
    for i=n-m+1:n
        dx_i = @view dx[:, i]
        recast!(dx_i, dstate)
        dneumann(state.quantum, H[i-n+m], dstate.quantum)
    end
    dmaster_stoch_dynamic_nl(dx, t, state, fstoch_quantum, fstoch_classical,
            rates_s, dstate, n-m)
end
function dmaster_stoch_dynamic_general_nl(dx::Array{Complex128, 2}, t::Float64, state::State{DenseOperator},
            fstoch_quantum::Union{Function, Void}, fstoch_classical::Union{Function, Void},
            fstoch_H::Void, fstoch_J::Function, rates::DecayRates, rates_s::DecayRates,
            dstate::State{DenseOperator}, tmp::DenseOperator, n::Int)
    result_J = fstoch_J(t, state.quantum, state.classical)
    @assert 2 <= length(result_J) <= 3
    if length(result_J) == 2
        J, Jdagger = result_J
        rates_ = rates
    else
        J, Jdagger, rates_ = result_J
    end
    l = length(J)

    for i=n-l+1:n
        dx_i = @view dx[:, i]
        recast!(dx_i, dstate)
        dlindblad(state.quantum, rates_, J, Jdagger, dstate.quantum, tmp, i-n+l)
        recast!(dstate, dx_i)
    end
    dmaster_stoch_dynamic_nl(dx, t, state, fstoch_quantum, fstoch_classical,
            rates_s, dstate, n-l)
end
function dmaster_stoch_dynamic_general_nl(dx::Array{Complex128, 2}, t::Float64,
            state::State{DenseOperator}, fstoch_quantum::Union{Function, Void},
            fstoch_classical::Union{Function, Void},
            fstoch_H::Function, fstoch_J::Function, rates::DecayRates, rates_s::DecayRates,
            dstate::State{DenseOperator}, tmp::DenseOperator, n::Int)
    H = fstoch_H(t, state.quantum, state.classical)
    m = length(H)

    for i=n-m+1:n
        dx_i = @view dx[:, i]
        recast!(dx_i, dstate)
        dneumann(state.quantum, H[i-n+m], dstate.quantum)
        recast!(dstate, dx_i)
    end
    dmaster_stoch_dynamic_general_nl(dx, t, state, fstoch_quantum, fstoch_classical,
            nothing, fstoch_J, rates, rates_s, dstate, tmp, n-m)
end

function integrate_master_stoch(tspan, df::Function, dg::Function,
                        rho0::State{DenseOperator}, fout::Union{Void, Function},
                        n::Int;
                        kwargs...)
    tspan_ = convert(Vector{Float64}, tspan)
    x0 = Vector{Complex128}(length(rho0))
    recast!(rho0, x0)
    state = copy(rho0)
    dstate = copy(rho0)
    integrate_stoch(tspan_, df, dg, x0, state, dstate, fout, n; kwargs...)
end

function recast!(state::State, x::SubArray{Complex128, 1})
    N = length(state.quantum)
    copy!(x, 1, state.quantum.data, 1, N)
    copy!(x, N+1, state.classical, 1, length(state.classical))
    x
end
function recast!(x::SubArray{Complex128, 1}, state::State)
    N = length(state.quantum)
    copy!(state.quantum.data, 1, x, 1, N)
    copy!(state.classical, 1, x, N+1, length(state.classical))
end

end # module
