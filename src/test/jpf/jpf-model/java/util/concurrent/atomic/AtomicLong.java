/*
 * SPDX-FileCopyrightText: 2014 United States Government, as represented by the Administrator of the National Aeronautics and Space Administration
 * SPDX-FileCopyrightText: 2026 Bernard Ladenthin <bernard.ladenthin@gmail.com>
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Derived from the jpf-core model class java/util/concurrent/atomic/AtomicLong.java
 * (github.com/javapathfinder/jpf-core): the modern addAndGet/incrementAndGet/getAndAdd surface was
 * added so a class under model check can call it (the upstream stub declared only legacy helpers).
 *
 * Copyright (C) 2014, United States Government, as represented by the
 * Administrator of the National Aeronautics and Space Administration.
 * All rights reserved.
 *
 * The Java Pathfinder core (jpf-core) platform is licensed under the
 * Apache License, Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License. You may obtain a copy of the License at
 *
 *        http://www.apache.org/licenses/LICENSE-2.0.
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package java.util.concurrent.atomic;

/**
 * MJI model class for java.util.concurrent.atomic.AtomicLong.
 *
 * <p>The stock jpf-core model only declared the legacy {@code attempt*} helpers, so a class under
 * model check that called the modern {@code addAndGet}/{@code incrementAndGet}/{@code getAndAdd}
 * surface died with {@code NoSuchMethodError} — even though the companion native peer
 * ({@code JPF_java_util_concurrent_atomic_AtomicLong}) already implemented every one of those as an
 * atomic MJI method (they showed up as "orphan NativePeer method" warnings for lack of a matching
 * model declaration). This model declares that surface so the peer binds; the plain-Java bodies are
 * the fallback if the peer is ever absent. Backing field name {@code value} matches the peer's
 * {@code env.getLongField(objRef, "value")} accessors. Not synchronized on purpose: atomicity comes
 * from the peer's single-MJI-call execution, mirroring the real CAS-based class.
 */
public class AtomicLong implements java.io.Serializable {

  private static final long serialVersionUID = 1927816293512124184L;

  private long value;

  public AtomicLong (long initialValue) {
    value = initialValue;
  }

  public AtomicLong () {
  }

  public final long get () {
    return value;
  }

  public final void set (long newValue) {
    value = newValue;
  }

  public final void lazySet (long newValue) {
    value = newValue;
  }

  public final long getAndSet (long newValue) {
    long old = value;
    value = newValue;
    return old;
  }

  public final boolean compareAndSet (long expect, long update) {
    if (value == expect) {
      value = update;
      return true;
    }
    return false;
  }

  public final boolean weakCompareAndSet (long expect, long update) {
    return compareAndSet(expect, update);
  }

  public final long getAndIncrement () {
    return value++;
  }

  public final long getAndDecrement () {
    return value--;
  }

  public final long getAndAdd (long delta) {
    long old = value;
    value += delta;
    return old;
  }

  public final long incrementAndGet () {
    return ++value;
  }

  public final long decrementAndGet () {
    return --value;
  }

  public final long addAndGet (long delta) {
    value += delta;
    return value;
  }

  public final int intValue () {
    return (int) value;
  }

  public final long longValue () {
    return value;
  }

  public final float floatValue () {
    return (float) value;
  }

  public final double doubleValue () {
    return (double) value;
  }

  @Override
  public String toString () {
    return Long.toString(value);
  }
}
